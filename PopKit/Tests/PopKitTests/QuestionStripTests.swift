import Foundation
import Testing
@testable import PopKit

/// IMP-25: while making a book, the page's question shows in a strip under the text (it
/// replaces the input bar) until it's answered, skipped or made stale, and never on the ending
/// or while a direction is re-writing the page behind.
struct QuestionStripTests {
    private let pond = StoryChoice(label: "The pond", symbol: "drop.fill", direction: "Pip looks at the pond.", followsPath: true)
    private let tree = StoryChoice(label: "Up a tree", symbol: "tree.fill", direction: "Pip climbs a tree.", followsPath: false)

    private func page(question: String? = "Where should Pip look?", kind: QuestionKind? = .choice, choices: [StoryChoice]? = nil) -> PageContent {
        PageContent(index: 1, text: "Pip lost his leaf.").with(question: question, kind: kind, choices: choices ?? [pond, tree])
    }

    @Test func aWrittenPagesQuestionShowsWithItsChoices() {
        let shown = page()
        let active = QuestionStrip.visible(page: shown, isEnding: false, directionInFlight: false, settled: [])
        #expect(active == ActiveQuestion(page: shown.key, ask: "Where should Pip look?", kind: .choice, choices: [pond, tree]))
    }

    @Test func aTalkOnlyQuestionShowsWithoutTiles() {
        let active = QuestionStrip.visible(page: page(question: "Can you roar like Rex?", kind: .talkOnly, choices: []), isEnding: false,
                                           directionInFlight: false, settled: [])
        #expect(active?.choices.isEmpty == true)
        #expect(active?.kind == .talkOnly)
    }

    @Test func nothingShowsWithoutAQuestionOrWords() {
        #expect(QuestionStrip.visible(page: nil, isEnding: false, directionInFlight: false, settled: []) == nil)
        #expect(QuestionStrip.visible(page: page(question: nil), isEnding: false, directionInFlight: false, settled: []) == nil)
        let empty = PageContent(index: 0, text: "").with(question: "Who?", kind: .choice, choices: [pond, tree])
        #expect(QuestionStrip.visible(page: empty, isEnding: false, directionInFlight: false, settled: []) == nil)
    }

    @Test func theEndingNeverAsksWhatHappensNext() {
        #expect(QuestionStrip.visible(page: page(), isEnding: true, directionInFlight: false, settled: []) == nil)
    }

    @Test func itHidesWhileADirectionIsInFlight() {
        #expect(QuestionStrip.visible(page: page(), isEnding: false, directionInFlight: true, settled: []) == nil)
    }

    @Test func itHidesOnceAnsweredSkippedOrMadeStale() {
        let shown = page()
        #expect(QuestionStrip.visible(page: shown, isEnding: false, directionInFlight: false, settled: [shown.key]) == nil)
    }

    @Test func aNewVersionOfThePageAsksAgain() {
        let shown = page()
        let rewritten = PageContent(id: shown.id, index: shown.index, version: shown.version + 1, text: "Pip lost his kite.")
            .with(question: "Where did the kite go?", kind: .choice, choices: [pond, tree])
        #expect(QuestionStrip.visible(page: rewritten, isEnding: false, directionInFlight: false, settled: [shown.key]) != nil)
    }

    @Test func aChoiceThatFollowsThePathNeedsNoRebuild() {
        #expect(QuestionStrip.input(for: pond) == nil)
    }

    @Test func aChoiceOffThePathIsAKidsChoiceTurn() {
        #expect(QuestionStrip.input(for: tree) == StoryTurnInput(kind: .choice, speaker: .kid, text: "Pip climbs a tree."))
    }

    @Test func aChoiceDirectionIsCappedAt120Characters() {
        let long = StoryChoice(label: "Long", symbol: "star.fill", direction: String(repeating: "a", count: 200), followsPath: false)
        #expect(QuestionStrip.input(for: long)?.text.count == 120)
    }

    @Test func aBlankOffPathChoiceSendsNothing() {
        let blank = StoryChoice(label: "Blank", symbol: "star.fill", direction: "  ", followsPath: false)
        #expect(QuestionStrip.input(for: blank) == nil)
    }
}
