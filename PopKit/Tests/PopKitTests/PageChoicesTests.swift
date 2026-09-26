import Foundation
import Testing
@testable import PopKit

/// IMP-25: each page may carry tap-to-steer choices for its question. They arrive with the
/// page, survive every later change to it (picture, layers, clip, placing, saving), and a
/// revision drops them with the words they were written for.
struct PageChoicesTests {
    private let pond = StoryChoice(label: "The pond", symbol: "drop.fill", direction: "Pip looks for the leaf at the pond.", followsPath: true)
    private let tree = StoryChoice(label: "Up a tree", symbol: "tree.fill", direction: "Pip climbs the oak tree to look.", followsPath: false)

    private func page(index: Int = 0) -> PageContent {
        PageContent(index: index, text: "Pip lost his leaf.", artPrompt: "a fox").with(question: "Where should Pip look?", kind: .choice, choices: [pond, tree])
    }

    @Test func theWireCarriesTheQuestionsKindAndChoices() throws {
        let json = #"""
        {"index":1,"text":"t","artPrompt":"a","question":"Where?","isEnding":false,"questionKind":"choice",
         "choices":[{"label":"The pond","symbol":"drop.fill","direction":"Pip looks for the leaf at the pond.","followsPath":true}]}
        """#
        let result = try JSONDecoder().decode(StoryTurnPageResult.self, from: Data(json.utf8))
        #expect(result.questionKind == .choice)
        #expect(result.choices == [pond])
    }

    @Test func anOlderServerWithoutChoicesStillDecodes() throws {
        let result = try JSONDecoder().decode(StoryTurnPageResult.self, from: Data(#"{"index":0,"text":"t","artPrompt":"a","question":"Who?"}"#.utf8))
        #expect(result.questionKind == nil)
        #expect(result.choices == nil)
    }

    @Test func anUnknownQuestionKindIsIgnoredNotAFailure() throws {
        let json = #"{"index":0,"text":"t","artPrompt":"a","question":"Who?","questionKind":"riddle","choices":[]}"#
        let result = try JSONDecoder().decode(StoryTurnPageResult.self, from: Data(json.utf8))
        #expect(result.questionKind == nil)
        #expect(result.text == "t")
    }

    @Test func aWrittenPageKeepsItsChoices() {
        let response = StoryTurnResponse(
            action: .page,
            page: StoryTurnPageResult(index: 0, text: "Pip lost his leaf.", artPrompt: "a", question: "Where should Pip look?",
                                      isEnding: false, questionKind: .choice, choices: [pond, tree]),
            bible: .empty, parentNote: nil, timings: StoryTurnTimings(modelMs: 1, safetyMs: 1)
        )
        let book = Book(kidId: UUID(), brief: StoryBrief(interests: []), createdAt: .now)
        let written = StoryEngine.applyPage(response, to: book).page
        #expect(written?.questionKind == .choice)
        #expect(written?.choices == [pond, tree])
    }

    @Test func aGatedOutQuestionLeavesNoChoices() {
        let cleared = page().with(question: "", kind: nil, choices: [])
        #expect(cleared.question == nil)
        #expect(cleared.questionKind == nil)
        #expect(cleared.choices == nil)
    }

    @Test func mediaChangesKeepTheChoices() {
        let changed = page().with(stillPath: "s.png").with(layers: PageLayers(platePath: "p", cutouts: [])).with(clipPath: "c.mp4")
            .with(motion: MotionParts(scene: "s", motion: "m")).with(text: "Pip lost his red leaf.")
        #expect(changed.choices == [pond, tree])
        #expect(changed.questionKind == .choice)
    }

    @Test func aRevisionDropsTheChoicesWithItsOldWords() {
        let revised = page().revised(text: "Pip found a new leaf.", artPrompt: nil)
        #expect(revised.choices == nil)
        #expect(revised.questionKind == nil)
    }

    @Test func placingAPageBehindKeepsItsChoices() {
        let onScreen = PageContent(index: 0, text: "Pip naps.")
        let (pages, placement) = DraftPages(pages: [onScreen], pendingNext: nil).placing(page(index: 1), currentIndex: 0)
        #expect(pages.pendingNext?.choices == [pond, tree])
        guard case let .behind(placed, _) = placement else {
            Issue.record("expected the page behind")
            return
        }
        #expect(placed.questionKind == .choice)
    }

    @Test func savedBooksKeepTheChoices() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "choices-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try FileBookStore(root: root)
        let book = Book(kidId: UUID(), brief: StoryBrief(interests: [], hero: .tile("fox")), pages: [page()], createdAt: .now)
        _ = try await store.save(book)
        let loaded = try await store.loadShelf().books.first
        #expect(loaded?.pages.first?.choices == [pond, tree])
        #expect(loaded?.brief.hero == .tile("fox"))
    }

    @Test func aChoiceMissingFollowsPathDecodesAsOffPath() throws {
        let choice = try JSONDecoder().decode(StoryChoice.self, from: Data(#"{"label":"l","symbol":"s","direction":"d"}"#.utf8))
        #expect(choice.followsPath == false)
    }
}
