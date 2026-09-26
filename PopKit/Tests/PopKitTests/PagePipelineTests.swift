import Foundation
import Testing
@testable import PopKit

/// Covers `PagePipeline`: the story-turn → art → motion-prompt sequence, preparing
/// a pending draft's art/motion only, cancelling a superseded run, failure
/// propagation, and the per-stage latency table (ROADMAP §2 `PagePipeline`).
struct PagePipelineTests {
    private let kid = KidProfile(firstName: "Maya", readingLevel: .earlyReader, interests: ["dinosaurs"])
    private let settings = ParentSettings()

    private func book() -> Book {
        Book(kidId: kid.id, brief: StoryBrief(interests: ["dinosaurs"]), createdAt: Date(timeIntervalSince1970: 0))
    }

    private func appendResponse(text: String, artPrompt: String) -> StoryTurnResponse {
        StoryTurnResponse(
            action: .append, page: StoryTurnPageResult(index: 0, text: text, artPrompt: artPrompt, breakSuggested: false),
            bible: .empty, parentNote: nil, timings: StoryTurnTimings(modelMs: 1, safetyMs: 1)
        )
    }

    private func collect(_ stream: AsyncStream<PagePipelineEvent>) async -> [PagePipelineEvent] {
        var events: [PagePipelineEvent] = []
        for await event in stream { events.append(event) }
        return events
    }

    @Test func runsStoryTurnThenArtThenMotionPromptInOrder() async throws {
        let server = FakePopServer()
        await server.onStoryTurn { _ in self.appendResponse(text: "A fox ran into a meadow.", artPrompt: "a fox in a meadow") }
        await server.onArt { _ in ArtResponse(path: "u/b/p0.png", url: "https://x/p0.png", width: 1344, height: 768, placeholder: false, ms: 1) }
        await server.onMotionPrompt { _ in MotionParts(scene: "a quiet meadow", motion: "grass sways") }

        let pipeline = PagePipeline(server: server)
        let draft = PageContent(index: 0, text: "")
        let input = StoryTurnInput(kind: .typed, speaker: .parent, text: "a fox appears")
        let events = await collect(pipeline.run(book: book(), kid: kid, settings: settings, currentDraft: draft, input: input))

        #expect(events.count == 3)
        guard case let .textReady(outcome) = events[0] else { Issue.record("expected textReady first, got \(events[0])"); return }
        #expect(outcome.currentDraft.text == "A fox ran into a meadow.")
        #expect(events[1] == .stillReady(pageIndex: 0, path: "u/b/p0.png", url: "https://x/p0.png"))
        #expect(events[2] == .motionReady(pageIndex: 0, prompt: MotionPromptBuilder.prompt(scene: "a quiet meadow", motion: "grass sways")))
    }

    @Test func aNewPageBreakAlsoPreparesTheArtAndMotionForThePendingNextDraft() async throws {
        let server = FakePopServer()
        await server.onStoryTurn { _ in
            StoryTurnResponse(
                action: .newPage, page: StoryTurnPageResult(index: 1, text: "They found berries.", artPrompt: "a forest path", breakSuggested: false),
                bible: .empty, parentNote: nil, timings: StoryTurnTimings(modelMs: 1, safetyMs: 1)
            )
        }
        await server.onArt { request in
            switch request.pageIndex {
            case 0: ArtResponse(path: "u/b/p0.png", url: "https://x/p0.png", width: 1344, height: 768, placeholder: false, ms: 1)
            default: ArtResponse(path: "u/b/p1.png", url: "https://x/p1.png", width: 1344, height: 768, placeholder: false, ms: 1)
            }
        }
        await server.onMotionPrompt { request in
            request.pageIndex == 0 ? MotionParts(scene: "a meadow", motion: "grass sways") : MotionParts(scene: "a forest path", motion: "leaves drift")
        }

        let pipeline = PagePipeline(server: server)
        let draft = PageContent(index: 0, text: "A fox ran into a meadow.", artPrompt: "a fox in a meadow")
        let input = StoryTurnInput(kind: .typed, speaker: .parent, text: "what happens next")
        let events = await collect(pipeline.run(book: book(), kid: kid, settings: settings, currentDraft: draft, input: input))

        #expect(events.count == 5)
        guard case let .textReady(outcome) = events[0] else { Issue.record("expected textReady first, got \(events[0])"); return }
        #expect(outcome.currentDraft == draft) // unchanged: new_page doesn't touch the current page
        #expect(outcome.pendingNextDraft?.index == 1)
        #expect(outcome.pendingNextDraft?.text == "They found berries.")
        #expect(events[1] == .stillReady(pageIndex: 0, path: "u/b/p0.png", url: "https://x/p0.png"))
        #expect(events[2] == .motionReady(pageIndex: 0, prompt: MotionPromptBuilder.prompt(scene: "a meadow", motion: "grass sways")))
        #expect(events[3] == .stillReady(pageIndex: 1, path: "u/b/p1.png", url: "https://x/p1.png"))
        #expect(events[4] == .motionReady(pageIndex: 1, prompt: MotionPromptBuilder.prompt(scene: "a forest path", motion: "leaves drift")))
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
        await server.onStoryTurn { _ in self.appendResponse(text: "text", artPrompt: "prompt") }
        await server.onArt { _ in throw ServerError.upstream("Gemini timed out") }
        await server.onMotionPrompt { _ in MotionParts(scene: "", motion: "") }

        let pipeline = PagePipeline(server: server)
        let draft = PageContent(index: 0, text: "")
        let input = StoryTurnInput(kind: .typed, speaker: .parent, text: "begin")
        let events = await collect(pipeline.run(book: book(), kid: kid, settings: settings, currentDraft: draft, input: input))

        #expect(events.count == 2)
        guard case .failed(let message) = events[1] else { Issue.record("expected a failed event, got \(events[1])"); return }
        #expect(message == ServerError.upstream("x").message)
    }

    @Test func aNewerRunForTheSamePageCancelsTheOlderOneAndItYieldsNothing() async throws {
        let server = FakePopServer()
        await server.onStoryTurn { request in
            if request.input?.text == "first" {
                try await Task.sleep(for: .milliseconds(200))
            }
            let text = request.input?.text ?? ""
            return self.appendResponse(text: text, artPrompt: "art for \(text)")
        }
        await server.onArt { _ in ArtResponse(path: "p", url: "u", width: 1, height: 1, placeholder: false, ms: 1) }
        await server.onMotionPrompt { _ in MotionParts(scene: "s", motion: "m") }

        let pipeline = PagePipeline(server: server)
        let draft = PageContent(index: 0, text: "")

        let firstStream = await pipeline.run(book: book(), kid: kid, settings: settings, currentDraft: draft, input: StoryTurnInput(kind: .typed, speaker: .parent, text: "first"))
        try await Task.sleep(for: .milliseconds(30))
        let secondStream = await pipeline.run(book: book(), kid: kid, settings: settings, currentDraft: draft, input: StoryTurnInput(kind: .typed, speaker: .parent, text: "second"))

        let firstEvents = await collect(firstStream)
        let secondEvents = await collect(secondStream)

        #expect(firstEvents.isEmpty)
        #expect(secondEvents.count == 3)
        guard case let .textReady(outcome) = secondEvents[0] else { Issue.record("expected textReady, got \(secondEvents[0])"); return }
        #expect(outcome.currentDraft.text == "second")
    }

    @Test func latencyTableIsEmptyUntilRunsCompleteThenReportsP50AndP90() async throws {
        let server = FakePopServer()
        await server.onStoryTurn { _ in self.appendResponse(text: "text", artPrompt: "prompt") }
        await server.onArt { _ in ArtResponse(path: "p", url: "u", width: 1, height: 1, placeholder: false, ms: 1) }
        await server.onMotionPrompt { _ in MotionParts(scene: "s", motion: "m") }

        let pipeline = PagePipeline(server: server)
        let empty = await pipeline.latencyTable()
        #expect(empty.storyTurn == nil && empty.art == nil && empty.motionPrompt == nil)

        for index in 0..<3 {
            let draft = PageContent(index: index, text: "")
            _ = await collect(pipeline.run(book: book(), kid: kid, settings: settings, currentDraft: draft, input: StoryTurnInput(kind: .typed, speaker: .parent, text: "go")))
        }

        let table = await pipeline.latencyTable()
        #expect(table.storyTurn != nil)
        #expect(table.art != nil)
        #expect(table.motionPrompt != nil)
        #expect(table.storyTurn!.p90 >= table.storyTurn!.p50)
    }
}
