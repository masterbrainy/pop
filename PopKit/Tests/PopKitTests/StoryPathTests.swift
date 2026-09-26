import Foundation
import Testing
@testable import PopKit

/// P-04: the story path. `path` plans (or re-plans from an index) and writes that page;
/// `page` writes the next page along the path; the page on screen never changes.
@Suite struct StoryPathTests {
    private let kid = KidProfile(firstName: "Sara", readingLevel: .earlyReader, interests: ["dragons"])
    private let path = ["Sara finds a kite.", "The kite pulls her up.", "She lands softly and sleeps. The end."]

    private func book(path: [String] = [], pages: [PageContent] = []) -> Book {
        Book(kidId: kid.id, brief: StoryBrief(interests: ["dragons"]), bible: StoryBible(characters: [], path: path),
             pages: pages, createdAt: Date(timeIntervalSince1970: 0))
    }

    private func pageResponse(index: Int, text: String, path: [String], action: StoryTurnAction = .page, note: String? = nil) -> StoryTurnResponse {
        StoryTurnResponse(
            action: action,
            page: action == .none ? nil : StoryTurnPageResult(index: index, text: text, artPrompt: "art \(index)",
                                                              question: "Q\(index)?", isEnding: index == path.count - 1),
            bible: StoryBible(title: "T", characters: [Character(id: "sara", name: "Sara", description: "blue dragon")], path: path),
            parentNote: note, timings: StoryTurnTimings(modelMs: 1, safetyMs: 1)
        )
    }

    @Test func aBibleSavedBeforeThePathLoadsWithAnEmptyPath() throws {
        let json = #"{"setting":"a meadow","characters":[],"directions":[]}"#
        let bible = try JSONDecoder().decode(StoryBible.self, from: Data(json.utf8))
        #expect(bible.path.isEmpty)
        let encoded = try JSONEncoder().encode(StoryBible(path: path))
        #expect(try JSONDecoder().decode(StoryBible.self, from: encoded).path == path)
    }

    @Test func theFirstPathRequestPlansFromTheBriefAtPageZero() {
        let request = StoryEngine.pathRequest(book: book(), kid: kid, settings: ParentSettings(), shownPages: [], index: 0, input: nil)
        #expect(request.mode == .path)
        #expect(request.index == 0)
        #expect(request.input == nil)
        #expect(request.pages.isEmpty)
    }

    @Test func aDirectionReplansFromThePageBehindWithOnlyTheShownPages() {
        let shown = [PageContent(index: 0, text: "Sara finds a kite.")]
        let direction = StoryTurnInput(kind: .typed, speaker: .parent, text: "make the kite purple")
        let request = StoryEngine.pathRequest(book: book(path: path, pages: shown), kid: kid, settings: ParentSettings(),
                                              shownPages: shown, index: 1, input: direction)
        #expect(request.mode == .path)
        #expect(request.index == 1)
        #expect(request.input == direction)
        #expect(request.pages == [StoryTurnPageRef(index: 0, text: "Sara finds a kite.")])
        #expect(request.bible.path == path)
    }

    @Test func aPageRequestWritesTheNextBeatWithNoInput() {
        let request = StoryEngine.pageRequest(book: book(path: path), kid: kid, settings: ParentSettings(), shownPages: [], index: 2)
        #expect(request.mode == .page)
        #expect(request.index == 2)
        #expect(request.input == nil)
    }

    @Test func applyingAPageGivesTheBookItsPathAndANewPageAtThatIndex() {
        let reference = Character(id: "sara", name: "Sara", description: "blue dragon", referencePath: "u/b/character-sara-v1.png")
        let before = book().with(bible: StoryBible(characters: [reference]))
        let outcome = StoryEngine.applyPage(pageResponse(index: 1, text: "The kite pulls her up.", path: path), to: before)
        #expect(outcome.book.bible.path == path)
        #expect(outcome.book.bible.characters.first?.referencePath == "u/b/character-sara-v1.png")
        #expect(outcome.page?.index == 1)
        #expect(outcome.page?.text == "The kite pulls her up.")
        #expect(outcome.page?.artPrompt == "art 1")
        #expect(outcome.page?.question == "Q1?")
        #expect(outcome.parentNote == nil)
    }

    @Test func aRefusedTurnKeepsTheBookAndOnlyCarriesTheNote() {
        let before = book(path: path)
        let outcome = StoryEngine.applyPage(pageResponse(index: 1, text: "", path: [], action: .none, note: "Let's keep it gentle."), to: before)
        #expect(outcome.page == nil)
        #expect(outcome.book == before)
        #expect(outcome.parentNote == "Let's keep it gentle.")
    }

    @Test func theLastBeatOfThePathIsTheEnding() {
        let bible = StoryBible(path: path)
        #expect(!bible.isEnding(pageIndex: 1))
        #expect(bible.isEnding(pageIndex: 2))
        #expect(!StoryBible().isEnding(pageIndex: 0))
        #expect(bible.hasPage(after: 1))
        #expect(!bible.hasPage(after: 2))
    }
}

@Suite struct PagePipelineBuildPageTests {
    private let kid = KidProfile(firstName: "Sara", readingLevel: .earlyReader, interests: [])

    private func collect(_ stream: AsyncStream<PagePipelineEvent>) async -> [PagePipelineEvent] {
        var events: [PagePipelineEvent] = []
        for await event in stream { events.append(event) }
        return events
    }

    private func server(text: String = "The kite pulls her up.", storyDelay: Duration = .zero) async -> FakePopServer {
        let server = FakePopServer()
        await server.onStoryTurn { request in
            try await Task.sleep(for: storyDelay)
            return StoryTurnResponse(
                action: .page,
                page: StoryTurnPageResult(index: request.index ?? 0, text: text, artPrompt: "art"),
                bible: StoryBible(path: ["a", "b"]), parentNote: nil, timings: StoryTurnTimings(modelMs: 1, safetyMs: 1)
            )
        }
        await server.onArt { request in
            ArtResponse(path: "u/b/page-\(request.pageIndex ?? 0).png", url: "https://example.test/p.png", width: 1, height: 1, placeholder: false, ms: 1)
        }
        await server.onMotionPrompt { _ in MotionParts(scene: "scene", motion: "bobs gently") }
        return server
    }

    @Test func writingAPageReleasesItsWordsWithoutWaitingForItsPicture() async throws {
        let server = await server()
        let pipeline = PagePipeline(server: server)
        let book = Book(kidId: kid.id, brief: StoryBrief(interests: []), createdAt: Date(timeIntervalSince1970: 0))
        let request = StoryEngine.pageRequest(book: book, kid: kid, settings: ParentSettings(), shownPages: [], index: 1)
        let events = await collect(await pipeline.writePage(request, book: book))

        guard events.count == 1, case let .pageWritten(outcome) = events[0] else {
            Issue.record("unexpected events \(events)")
            return
        }
        #expect(outcome.page?.index == 1)
        // The words end the text lane; painting is the art lane's job.
        let artCallCount = await server.artCalls.count
        #expect(artCallCount == 0)
    }

    @Test func aNewBuildForTheSamePageCancelsTheOldOneQuietly() async throws {
        let server = await server(storyDelay: .milliseconds(150))
        let pipeline = PagePipeline(server: server)
        let book = Book(kidId: kid.id, brief: StoryBrief(interests: []), createdAt: Date(timeIntervalSince1970: 0))
        let request = StoryEngine.pageRequest(book: book, kid: kid, settings: ParentSettings(), shownPages: [], index: 1)
        let first = await pipeline.writePage(request, book: book)
        let second = await pipeline.writePage(request, book: book)
        let firstEvents = await collect(first)
        let secondEvents = await collect(second)
        #expect(firstEvents.isEmpty)
        #expect(secondEvents.count == 1)
    }
}
