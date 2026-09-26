import Foundation
import Testing
@testable import PopKit

/// Covers `PagePipeline` behavior not already covered by `StoryPathTests`'s
/// `PagePipelineBuildPageTests`: preparing a pending draft's art/motion only,
/// failure propagation, and the per-stage latency table (ROADMAP §2 `PagePipeline`).
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

    private func collect(_ stream: AsyncStream<PagePipelineEvent>) async -> [PagePipelineEvent] {
        var events: [PagePipelineEvent] = []
        for await event in stream { events.append(event) }
        return events
    }

    @Test func preparePendingDraftSkipsStoryTurnAndOnlyRunsArtAndMotion() async throws {
        let server = FakePopServer()
        await server.onArt { _ in ArtResponse(path: "u/b/p1.png", url: "https://x/p1.png", width: 1344, height: 768, placeholder: false, ms: 1) }
        await server.onMotionPrompt { _ in MotionParts(scene: "a forest path", motion: "leaves drift") }

        let pipeline = PagePipeline(server: server)
        let page = PageContent(index: 1, text: "They went looking for berries.", artPrompt: "a forest path")
        let events = await collect(pipeline.preparePendingDraft(page, book: book()))

        #expect(events.count == 2)
        #expect(events[0] == .stillReady(pageIndex: 1, path: "u/b/p1.png", url: "https://x/p1.png"))
        let storyTurnCallCount = await server.storyTurnCalls.count
        #expect(storyTurnCallCount == 0)
    }

    @Test func aFailingStageEmitsAFriendlyFailedEventInsteadOfThrowing() async throws {
        let server = FakePopServer()
        await server.onStoryTurn { _ in self.pageResponse(index: 0, text: "text", artPrompt: "prompt") }
        await server.onArt { _ in throw ServerError.upstream("Gemini timed out") }
        await server.onMotionPrompt { _ in MotionParts(scene: "", motion: "") }

        let pipeline = PagePipeline(server: server)
        let book = book()
        let request = StoryEngine.pageRequest(book: book, kid: kid, settings: settings, shownPages: [], index: 0)
        let events = await collect(pipeline.buildPage(request, book: book))

        #expect(events.count == 2)
        guard case .failed(let message) = events[1] else { Issue.record("expected a failed event, got \(events[1])"); return }
        #expect(message == ServerError.upstream("x").message + "\nGemini timed out")
    }

    @Test func latencyTableIsEmptyUntilRunsCompleteThenReportsP50AndP90() async throws {
        let server = FakePopServer()
        await server.onStoryTurn { request in self.pageResponse(index: request.index ?? 0, text: "text", artPrompt: "prompt") }
        await server.onArt { _ in ArtResponse(path: "p", url: "u", width: 1, height: 1, placeholder: false, ms: 1) }
        await server.onMotionPrompt { _ in MotionParts(scene: "s", motion: "m") }

        let pipeline = PagePipeline(server: server)
        let empty = await pipeline.latencyTable()
        #expect(empty.storyTurn == nil && empty.art == nil && empty.motionPrompt == nil)

        let book = book()
        for index in 0..<3 {
            let request = StoryEngine.pageRequest(book: book, kid: kid, settings: settings, shownPages: [], index: index)
            _ = await collect(pipeline.buildPage(request, book: book))
        }

        let table = await pipeline.latencyTable()
        #expect(table.storyTurn != nil)
        #expect(table.art != nil)
        #expect(table.motionPrompt != nil)
        #expect(table.storyTurn!.p90 >= table.storyTurn!.p50)
    }
}
