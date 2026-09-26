import Foundation
import Testing
@testable import PopKit

/// Covers `PagePipeline` behavior not already covered by `StoryPathTests`'s
/// `PagePipelineBuildPageTests`: the art lane (painting a page by id and version, apart from
/// the words), failure propagation, and the per-stage latency table (ROADMAP §2 `PagePipeline`).
struct PagePipelineTests {
    private let kid = KidProfile(firstName: "Maya", readingLevel: .earlyReader, interests: ["dinosaurs"])
    private let settings = ParentSettings()

    private func book() -> Book {
        Book(kidId: kid.id, brief: StoryBrief(interests: ["dinosaurs"]), createdAt: Date(timeIntervalSince1970: 0))
    }

    private func pageResponse(index: Int, text: String, artPrompt: String) -> StoryTurnResponse {
        StoryTurnResponse(
            action: .page, page: StoryTurnPageResult(index: index, text: text, artPrompt: artPrompt),
            bible: .empty, parentNote: nil, timings: StoryTurnTimings(modelMs: 1, safetyMs: 1)
        )
    }

    private func collect(_ stream: AsyncStream<PagePipelineEvent>?) async -> [PagePipelineEvent] {
        guard let stream else { return [] }
        var events: [PagePipelineEvent] = []
        for await event in stream { events.append(event) }
        return events
    }

    private func paintingServer(artDelay: Duration = .zero) async -> FakePopServer {
        let server = FakePopServer()
        await server.onArt { request in
            try await Task.sleep(for: artDelay)
            return ArtResponse(path: "u/b/page-\(request.pageIndex ?? 0)-v\(request.version ?? 0).png", url: "https://x/p.png",
                               width: 1344, height: 768, placeholder: false, ms: 1)
        }
        await server.onMotionPrompt { _ in MotionParts(scene: "a forest path", motion: "leaves drift") }
        return server
    }

    @Test func paintingSkipsStoryTurnAndReportsByPageIdAndVersion() async throws {
        let server = await paintingServer()
        let pipeline = PagePipeline(server: server)
        let page = PageContent(index: 1, version: 2, text: "They went looking for berries.", artPrompt: "a forest path")

        let events = await collect(await pipeline.paint(page, book: book()))

        #expect(events.count == 2)
        #expect(events[0] == .stillReady(page.key, path: "u/b/page-1-v2.png", url: "https://x/p.png"))
        guard case let .motionReady(key, prompt) = events[1] else { Issue.record("expected motionReady, got \(events[1])"); return }
        #expect(key == page.key)
        #expect(!prompt.isEmpty)
        let storyTurnCallCount = await server.storyTurnCalls.count
        #expect(storyTurnCallCount == 0)
        let artVersions = await server.artCalls.compactMap(\.version)
        #expect(artVersions == [2])
    }

    @Test func paintingAPageThatIsAlreadyPaintingDoesNotRestartIt() async throws {
        let server = await paintingServer(artDelay: .milliseconds(100))
        let pipeline = PagePipeline(server: server)
        let page = PageContent(index: 1, text: "Berries.", artPrompt: "a forest path")

        let first = await pipeline.paint(page, book: book())
        let again = await pipeline.paint(page, book: book())

        #expect(again == nil)
        let events = await collect(first)
        #expect(events.count == 2)
        let artCallCount = await server.artCalls.count
        #expect(artCallCount == 1)
    }

    @Test func aNewVersionOfThePageRestartsItsPaintingAndTheOldRunEndsQuietly() async throws {
        let server = await paintingServer(artDelay: .milliseconds(100))
        let pipeline = PagePipeline(server: server)
        let page = PageContent(index: 1, text: "Berries.", artPrompt: "a forest path")
        let revised = page.revised(text: "Snowy berries.", artPrompt: "a snowy forest path")

        let first = await pipeline.paint(page, book: book())
        let second = await pipeline.paint(revised, book: book())

        #expect(await collect(first).isEmpty)
        let events = await collect(second)
        #expect(events.first == .stillReady(revised.key, path: "u/b/page-1-v2.png", url: "https://x/p.png"))
    }

    @Test func writingANewPageBehindDoesNotStopTheOldPageBehindFromPainting() async throws {
        // A direction starts rewriting the page behind; if the parent turns before its words
        // land, the old page behind shows, so its picture must keep going (PRD S7).
        let server = await paintingServer(artDelay: .milliseconds(100))
        await server.onStoryTurn { request in
            try await Task.sleep(for: .milliseconds(20))
            return self.pageResponse(index: request.index ?? 0, text: "Snow falls.", artPrompt: "snow")
        }
        let pipeline = PagePipeline(server: server)
        let oldBehind = PageContent(index: 1, text: "The kite flies.", artPrompt: "a kite")
        let book = book()

        let painting = await pipeline.paint(oldBehind, book: book)
        let request = StoryEngine.pathRequest(book: book, kid: kid, settings: settings, shownPages: [], index: 1,
                                              input: StoryTurnInput(kind: .typed, speaker: .parent, text: "make it snow"))
        let rewrite = await pipeline.writePage(request, book: book)

        #expect(await collect(rewrite).count == 1)
        let paintEvents = await collect(painting)
        #expect(paintEvents.first == .stillReady(oldBehind.key, path: "u/b/page-1-v1.png", url: "https://x/p.png"))
    }

    @Test func cancellingAPaintingStopsItQuietly() async throws {
        let server = await paintingServer(artDelay: .milliseconds(200))
        let pipeline = PagePipeline(server: server)
        let page = PageContent(index: 1, text: "Berries.", artPrompt: "a forest path")

        let painting = await pipeline.paint(page, book: book())
        await pipeline.cancelPaint(pageId: page.id)

        #expect(await collect(painting).isEmpty)
        // Cancelled, so it may be painted again later.
        #expect(await pipeline.paint(page, book: book()) != nil)
    }

    /// IMP-10: when moderation flags the picture twice, `art` returns `placeholder: true` with
    /// an empty path. Motion-prompt must not be called with that empty still (it fails its
    /// schema); the page reports it has no picture instead.
    @Test func aModeratedPlaceholderPictureSkipsMotionAndSaysThePictureIsUnavailable() async throws {
        let server = FakePopServer()
        await server.onStoryTurn { _ in self.pageResponse(index: 0, text: "text", artPrompt: "prompt") }
        await server.onArt { _ in ArtResponse(path: "", url: "", width: 1344, height: 768, placeholder: true, ms: 1) }
        await server.onMotionPrompt { _ in MotionParts(scene: "s", motion: "m") }

        let pipeline = PagePipeline(server: server)
        let page = PageContent(index: 0, text: "text", artPrompt: "prompt")
        let events = await collect(await pipeline.paint(page, book: book()))

        #expect(events == [.pictureUnavailable(page.key)])
        #expect(await server.motionPromptCalls.isEmpty)
    }

    @Test func aFailingStageEmitsAFriendlyFailedEventInsteadOfThrowing() async throws {
        let server = FakePopServer()
        await server.onArt { _ in throw ServerError.upstream("Gemini timed out") }
        await server.onMotionPrompt { _ in MotionParts(scene: "", motion: "") }

        let pipeline = PagePipeline(server: server)
        let page = PageContent(index: 0, text: "text", artPrompt: "prompt")
        let events = await collect(await pipeline.paint(page, book: book()))

        #expect(events.count == 1)
        guard case .failed(let message) = events[0] else { Issue.record("expected a failed event, got \(events[0])"); return }
        #expect(message == ServerError.upstream("x").message + "\nGemini timed out")
    }

    @Test func aFailingStoryTurnEmitsAFriendlyFailedEvent() async throws {
        let server = FakePopServer()
        await server.onStoryTurn { _ in throw ServerError.upstream("model timed out") }

        let pipeline = PagePipeline(server: server)
        let book = book()
        let request = StoryEngine.pageRequest(book: book, kid: kid, settings: settings, shownPages: [], index: 0)
        let events = await collect(await pipeline.writePage(request, book: book))

        #expect(events.count == 1)
        guard case .failed = events[0] else { Issue.record("expected a failed event, got \(events[0])"); return }
    }

    @Test func latencyTableIsEmptyUntilRunsCompleteThenReportsP50AndP90() async throws {
        let server = await paintingServer()
        await server.onStoryTurn { request in self.pageResponse(index: request.index ?? 0, text: "text", artPrompt: "prompt") }

        let pipeline = PagePipeline(server: server)
        let empty = await pipeline.latencyTable()
        #expect(empty.storyTurn == nil && empty.art == nil && empty.motionPrompt == nil)

        let book = book()
        for index in 0..<3 {
            let request = StoryEngine.pageRequest(book: book, kid: kid, settings: settings, shownPages: [], index: index)
            for event in await collect(await pipeline.writePage(request, book: book)) {
                if case let .pageWritten(outcome) = event, let page = outcome.page {
                    _ = await collect(await pipeline.paint(page, book: outcome.book))
                }
            }
        }

        let table = await pipeline.latencyTable()
        #expect(table.storyTurn != nil)
        #expect(table.art != nil)
        #expect(table.motionPrompt != nil)
        #expect(table.storyTurn!.p90 >= table.storyTurn!.p50)
    }
}
