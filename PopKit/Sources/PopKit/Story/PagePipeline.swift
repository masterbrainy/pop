import Foundation

/// One page's generation progress (docs/CONTRACTS.md §3; ROADMAP §2 `PagePipeline`). The text
/// lane reports `pageWritten`; the art lane reports `stillReady` then `motionReady` for one
/// version of one page. Either lane may report `failed`.
public enum PagePipelineEvent: Sendable, Equatable {
    /// A `path` or `page` call wrote a page (or refused with a note), P-04.
    case pageWritten(PathOutcome)
    case stillReady(PageKey, path: String, url: String)
    case motionReady(PageKey, prompt: String)
    /// Moderation turned the picture away twice (`art` returned a placeholder), so this page
    /// has no picture and no motion; the app shows a friendly card instead of "Painting…".
    case pictureUnavailable(PageKey)
    case failed(String)
}

/// p50/p90 elapsed seconds for one pipeline stage, across every run so far.
public struct LatencyStats: Sendable, Equatable {
    public let p50: TimeInterval
    public let p90: TimeInterval

    public init(p50: TimeInterval, p90: TimeInterval) {
        self.p50 = p50
        self.p90 = p90
    }
}

/// The per-stage latency table used for the Phase 2/3 exit criteria's p50 report.
public struct LatencyTable: Sendable, Equatable {
    public let storyTurn: LatencyStats?
    public let art: LatencyStats?
    public let motionPrompt: LatencyStats?

    public init(storyTurn: LatencyStats?, art: LatencyStats?, motionPrompt: LatencyStats?) {
        self.storyTurn = storyTurn
        self.art = art
        self.motionPrompt = motionPrompt
    }
}

/// Builds pages in two lanes, so a page's words never wait for another page's picture.
/// The text lane writes a page (`path`/`page` story-turn call) and ends as soon as the words
/// land; it's keyed by page index, so a newer write for that index (a direction's rebuild of
/// the page behind) cancels the older one. The art lane paints one version of one page and
/// prepares its motion prompt; it's keyed by page id, so writing a new page behind leaves the
/// old one painting (the parent may still turn to it), and the same page isn't restarted
/// unless its version or art prompt changed (ROADMAP §2 `PagePipeline`).
public actor PagePipeline {
    private let server: PopServer
    private let now: @Sendable () -> Date

    private var writes: [Int: (run: UUID, task: Task<Void, Never>)] = [:]
    private var paints: [UUID: (run: UUID, key: PageKey, artPrompt: String?, task: Task<Void, Never>)] = [:]
    private var storyTurnSamples: [TimeInterval] = []
    private var artSamples: [TimeInterval] = []
    private var motionPromptSamples: [TimeInterval] = []

    public init(server: PopServer, now: @escaping @Sendable () -> Date = Date.init) {
        self.server = server
        self.now = now
    }

    /// The text lane: the `path` or `page` call in `request`, for the page at its index (P-04).
    /// Cancels an earlier write for that index. The stream ends once the words land.
    public func writePage(_ request: StoryTurnRequest, book: Book) -> AsyncStream<PagePipelineEvent> {
        let index = request.index ?? 0
        writes[index]?.task.cancel()
        let run = UUID()
        let (stream, continuation) = AsyncStream<PagePipelineEvent>.makeStream()
        let task = Task { await self.executeWrite(run: run, request: request, book: book, continuation: continuation) }
        writes[index] = (run, task)
        return stream
    }

    /// The art lane: paints `page` and prepares its motion prompt. Nil when this version of the
    /// page, with the same art prompt, is already painting; a new version (or art prompt)
    /// replaces the earlier run for the page.
    public func paint(_ page: PageContent, book: Book) -> AsyncStream<PagePipelineEvent>? {
        if let current = paints[page.id] {
            guard current.key != page.key || current.artPrompt != page.artPrompt else { return nil }
            current.task.cancel()
        }
        let run = UUID()
        let (stream, continuation) = AsyncStream<PagePipelineEvent>.makeStream()
        let task = Task { await self.executePaint(run: run, page: page, book: book, continuation: continuation) }
        paints[page.id] = (run, page.key, page.artPrompt, task)
        return stream
    }

    /// Cancels any in-flight write for this page index, without starting a new one.
    public func cancel(pageIndex: Int) {
        writes[pageIndex]?.task.cancel()
        writes[pageIndex] = nil
    }

    /// Stops painting this page (it was replaced before its picture landed).
    public func cancelPaint(pageId: UUID) {
        paints[pageId]?.task.cancel()
        paints[pageId] = nil
    }

    public func latencyTable() -> LatencyTable {
        LatencyTable(
            storyTurn: Self.stats(from: storyTurnSamples),
            art: Self.stats(from: artSamples),
            motionPrompt: Self.stats(from: motionPromptSamples)
        )
    }

    // MARK: - lanes

    private func executeWrite(
        run: UUID, request: StoryTurnRequest, book: Book, continuation: AsyncStream<PagePipelineEvent>.Continuation
    ) async {
        defer {
            let index = request.index ?? 0
            if writes[index]?.run == run { writes[index] = nil }
            continuation.finish()
        }
        await reportingFailures(to: continuation) {
            let response = try await self.timedStoryTurn { try await self.server.storyTurn(request) }
            try Task.checkCancellation()
            continuation.yield(.pageWritten(StoryEngine.applyPage(response, to: book)))
        }
    }

    private func executePaint(
        run: UUID, page: PageContent, book: Book, continuation: AsyncStream<PagePipelineEvent>.Continuation
    ) async {
        defer {
            if paints[page.id]?.run == run { paints[page.id] = nil }
            continuation.finish()
        }
        await reportingFailures(to: continuation) {
            let artRequest = ArtRequest(
                bookId: book.id, kind: .page, pageIndex: page.index, version: page.version,
                prompt: page.artPrompt ?? "", characters: book.bible.characters
            )
            let art = try await self.timedArt { try await self.server.art(artRequest) }
            try Task.checkCancellation()
            guard !art.placeholder, !art.path.isEmpty else {
                continuation.yield(.pictureUnavailable(page.key))
                return
            }
            continuation.yield(.stillReady(page.key, path: art.path, url: art.url))

            let motionRequest = MotionPromptRequest(bookId: book.id, pageIndex: page.index, text: page.text, stillPath: art.path)
            let parts = try await self.timedMotionPrompt { try await self.server.motionPrompt(motionRequest) }
            try Task.checkCancellation()
            continuation.yield(.motionReady(page.key, prompt: MotionPromptBuilder.prompt(parts)))
        }
    }

    /// Runs `body`, turning a failure into a friendly `failed` event; a cancelled run (replaced
    /// by a newer one) stays quiet.
    private func reportingFailures(
        to continuation: AsyncStream<PagePipelineEvent>.Continuation, _ body: () async throws -> Void
    ) async {
        do {
            try await body()
        } catch where error is CancellationError || Task.isCancelled {
            // Superseded by a newer run (a cancelled request may surface as another error); stay quiet.
        } catch let error as ServerError {
            continuation.yield(.failed(error.message + "\n" + error.serverDetail))
        } catch {
            continuation.yield(.failed("\(error)"))
        }
    }

    // MARK: - timing

    private func timedStoryTurn<T>(_ operation: () async throws -> T) async throws -> T {
        let start = now()
        let result = try await operation()
        storyTurnSamples.append(now().timeIntervalSince(start))
        return result
    }

    private func timedArt<T>(_ operation: () async throws -> T) async throws -> T {
        let start = now()
        let result = try await operation()
        artSamples.append(now().timeIntervalSince(start))
        return result
    }

    private func timedMotionPrompt<T>(_ operation: () async throws -> T) async throws -> T {
        let start = now()
        let result = try await operation()
        motionPromptSamples.append(now().timeIntervalSince(start))
        return result
    }

    private static func stats(from samples: [TimeInterval]) -> LatencyStats? {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        return LatencyStats(p50: percentile(sorted, 0.5), p90: percentile(sorted, 0.9))
    }

    private static func percentile(_ sorted: [TimeInterval], _ fraction: Double) -> TimeInterval {
        guard !sorted.isEmpty else { return 0 }
        let rank = Int((fraction * Double(sorted.count - 1)).rounded())
        return sorted[min(max(rank, 0), sorted.count - 1)]
    }
}
