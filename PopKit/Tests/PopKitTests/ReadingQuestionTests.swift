import Foundation
import Testing
@testable import PopKit

/// PRD C3: each page carries one question for the parent to ask about it.
@Suite struct ReadingQuestionTests {
    private func response(_ action: StoryTurnAction, index: Int = 0, text: String, question: String?) -> StoryTurnResponse {
        StoryTurnResponse(
            action: action,
            page: StoryTurnPageResult(index: index, text: text, artPrompt: "art", breakSuggested: false, question: question),
            bible: .empty, parentNote: nil, timings: StoryTurnTimings(modelMs: 1, safetyMs: 1)
        )
    }

    private let book = Book(kidId: UUID(), brief: StoryBrief(interests: []), createdAt: Date(timeIntervalSince1970: 0))

    @Test func anAppendedPageTakesTheNewQuestion() {
        let draft = PageContent(index: 0, text: "Maya flies.")
        let outcome = StoryEngine.apply(response(.append, text: "Maya flies. She sees a kite.", question: "What does Maya see?"), to: book, currentDraft: draft)
        #expect(outcome.currentDraft.question == "What does Maya see?")
    }

    @Test func aRevisedPageAndANewPageTakeTheirQuestions() {
        let draft = PageContent(index: 0, text: "Maya flies.")
        let revised = StoryEngine.apply(response(.reviseCurrent, text: "Maya soars.", question: "How high?"), to: book, currentDraft: draft)
        #expect(revised.currentDraft.question == "How high?")
        let next = StoryEngine.apply(response(.newPage, index: 1, text: "Then she lands.", question: "Where does she land?"), to: book, currentDraft: draft)
        #expect(next.pendingNextDraft?.question == "Where does she land?")
        #expect(next.currentDraft.question == nil)
    }

    @Test func anEmptyQuestionIsStoredAsNone() {
        let outcome = StoryEngine.apply(response(.append, text: "Maya flies.", question: "  "), to: book, currentDraft: PageContent(index: 0, text: ""))
        #expect(outcome.currentDraft.question == nil)
    }

    @Test func mediaUpdatesKeepTheQuestion() {
        let page = PageContent(index: 0, text: "Maya flies.").with(question: "Who flies?")
        #expect(page.with(stillPath: "s.png").with(clipPath: "c.mp4").with(text: "Maya flies high.").question == "Who flies?")
    }

    @Test func booksSavedBeforeQuestionsStillLoad() throws {
        let json = #"{"id":"6F1C2E4A-1111-4B2C-9D3E-222233334444","index":0,"version":1,"text":"Old page."}"#
        let page = try JSONDecoder().decode(PageContent.self, from: Data(json.utf8))
        #expect(page.question == nil)
        let result = try JSONDecoder().decode(StoryTurnPageResult.self, from: Data(#"{"index":0,"text":"t","artPrompt":"a","breakSuggested":false}"#.utf8))
        #expect(result.question == nil)
    }
}
