import Foundation

/// One page's generation progress: text, then its still, then its motion prompt —
/// or a failure at any stage (docs/CONTRACTS.md §3; ROADMAP §2 `PagePipeline`).
public enum PagePipelineEvent: Sendable, Equatable {
    case textReady(PageContent)
    case stillReady(path: String, url: String)
    case motionReady(prompt: String)
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

/// Runs one page through story-turn → art → motion-prompt, emitting progress as each
/// stage lands. A page's index identifies its in-flight run: starting a new one (a
/// revision, or the next page) cancels whatever was still running for that same
/// index, so only the latest survives (ROADMAP §2 `PagePipeline`).
public actor PagePipeline {
    private let server: PopServer
    private let now: @Sendable () -> Date

    private var runs: [Int: (id: UUID, task: Task<Void, Never>)] = [:]
    private var storyTurnSamples: [TimeInterval] = []
    private var artSamples: [TimeInterval] = []
    private var motionPromptSamples: [TimeInterval] = []

    public init(server: PopServer, now: @escaping @Sendable () -> Date = Date.init) {
        self.server = server
        self.now = now
    }

    /// The full sequence for the page currently being drafted: story-turn (built from
    /// `book`/`kid`/`settings`/`currentDraft`/`input`), then art and motion-prompt for
    /// whatever text comes back.
    @discardableResult
    public func run(book: Book, kid: KidProfile, settings: ParentSettings, currentDraft: PageContent, input: StoryTurnInput) -> AsyncStream<PagePipelineEvent> {
        start(pageIndex: currentDraft.index) { [self] runID, continuation in
            await self.executeFullTurn(runID: runID, book: book, kid: kid, settings: settings, currentDraft: currentDraft, input: input, continuation: continuation)
        }
    }

    /// Art and motion-prompt only, for a page whose text is already known — used to
    /// prepare the next page early, once its draft appears from a `new_page` turn.
    @discardableResult
    public func preparePendingDraft(_ page: PageContent, book: Book) -> AsyncStream<PagePipelineEvent> {
        start(pageIndex: page.index) { [self] runID, continuation in
            await self.executeArtAndMotionOnly(runID: runID, page: page, book: book, continuation: continuation)
        }
    }

    /// Cancels any in-flight run for this page index, without starting a new one.
    public func cancel(pageIndex: Int) {
        runs[pageIndex]?.task.cancel()
        runs[pageIndex] = nil
    }

    public func latencyTable() -> LatencyTable {
        LatencyTable(
            storyTurn: Self.stats(from: storyTurnSamples),
            art: Self.stats(from: artSamples),
            motionPrompt: Self.stats(from: motionPromptSamples)
        )
    }

    // MARK: - starting and superseding runs

    private func start(
        pageIndex: Int, _ body: @escaping @Sendable (UUID, AsyncStream<PagePipelineEvent>.Continuation) async -> Void
    ) -> AsyncStream<PagePipelineEvent> {
        runs[pageIndex]?.task.cancel()

        let runID = UUID()
        let (stream, continuation) = AsyncStream<PagePipelineEvent>.makeStream()
        let task = Task {
            await body(runID, continuation)
        }
        runs[pageIndex] = (runID, task)
        return stream
    }

    private func finish(runID: UUID, pageIndex: Int) {
        if runs[pageIndex]?.id == runID {
            runs[pageIndex] = nil
        }
    }

    // MARK: - stage sequences

    private func executeFullTurn(
        runID: UUID, book: Book, kid: KidProfile, settings: ParentSettings, currentDraft: PageContent, input: StoryTurnInput,
        continuation: AsyncStream<PagePipelineEvent>.Continuation
    ) async {
        defer {
            finish(runID: runID, pageIndex: currentDraft.index)
            continuation.finish()
        }
        do {
            let request = StoryEngine.turnRequest(book: book, kid: kid, settings: settings, currentDraft: currentDraft, input: input)
            let response = try await timedStoryTurn { try await self.server.storyTurn(request) }
            try Task.checkCancellation()

            let outcome = StoryEngine.apply(response, to: book, currentDraft: currentDraft)
            continuation.yield(.textReady(outcome.currentDraft))
            try Task.checkCancellation()

            try await runArtAndMotion(page: outcome.currentDraft, book: outcome.book, continuation: continuation)
        } catch is CancellationError {
            // superseded by a newer run for the same page; stay quiet.
        } catch let error as ServerError {
            continuation.yield(.failed(error.message))
        } catch {
            continuation.yield(.failed("\(error)"))
        }
    }

    private func executeArtAndMotionOnly(
        runID: UUID, page: PageContent, book: Book, continuation: AsyncStream<PagePipelineEvent>.Continuation
    ) async {
        defer {
            finish(runID: runID, pageIndex: page.index)
            continuation.finish()
        }
        do {
            continuation.yield(.textReady(page))
            try await runArtAndMotion(page: page, book: book, continuation: continuation)
        } catch is CancellationError {
        } catch let error as ServerError {
            continuation.yield(.failed(error.message))
        } catch {
            continuation.yield(.failed("\(error)"))
        }
    }

    private func runArtAndMotion(page: PageContent, book: Book, continuation: AsyncStream<PagePipelineEvent>.Continuation) async throws {
        let artRequest = ArtRequest(
            bookId: book.id, kind: .page, pageIndex: page.index, version: page.version,
            prompt: page.artPrompt ?? "", characters: book.bible.characters
        )
        let art = try await timedArt { try await self.server.art(artRequest) }
        try Task.checkCancellation()
        continuation.yield(.stillReady(path: art.path, url: art.url))

        let motionRequest = MotionPromptRequest(bookId: book.id, pageIndex: page.index, text: page.text, stillPath: art.path)
        let parts = try await timedMotionPrompt { try await self.server.motionPrompt(motionRequest) }
        try Task.checkCancellation()
        continuation.yield(.motionReady(prompt: MotionPromptBuilder.prompt(parts)))
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
