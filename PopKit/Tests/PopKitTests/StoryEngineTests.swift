import Foundation
import Testing
@testable import PopKit

/// Covers `StoryEngine`: applying a story-turn response to a book and its current
/// page draft (docs/CONTRACTS.md §3 `story-turn`), request building, and the
/// reading-level word-count check (PRD §8.7).
struct StoryEngineTests {
    private let kid = KidProfile(firstName: "Maya", readingLevel: .earlyReader, interests: ["dinosaurs"])
    private let settings = ParentSettings(avoidTopics: ["monsters"])

    private func book(pages: [PageContent] = [], bible: StoryBible = .empty) -> Book {
        Book(kidId: kid.id, brief: StoryBrief(interests: ["dinosaurs"], teach: "sharing"), bible: bible, pages: pages, createdAt: Date(timeIntervalSince1970: 0))
    }

    private func timings() -> StoryTurnTimings { StoryTurnTimings(modelMs: 10, safetyMs: 5) }

    // MARK: - apply

    @Test func appendReplacesTheCurrentDraftsTextAndArtPromptAndCarriesTheBibleForward() {
        let draft = PageContent(index: 0, text: "Once upon a", artPrompt: "a quiet meadow")
        let bible = StoryBible(setting: "a meadow", directions: ["make it rain"])
        let response = StoryTurnResponse(
            action: .append,
            page: StoryTurnPageResult(index: 0, text: "Once upon a time there was a dinosaur", artPrompt: "a meadow with a dinosaur", breakSuggested: false),
            bible: bible, parentNote: nil, timings: timings()
        )

        let outcome = StoryEngine.apply(response, to: book(bible: .empty), currentDraft: draft)

        #expect(outcome.currentDraft.text == "Once upon a time there was a dinosaur")
        #expect(outcome.currentDraft.artPrompt == "a meadow with a dinosaur")
        #expect(outcome.currentDraft.id == draft.id && outcome.currentDraft.version == draft.version)
        #expect(outcome.book.bible == bible)
        #expect(outcome.pendingNextDraft == nil)
        #expect(outcome.parentNote == nil)
    }

    @Test func newPageStoresAPendingDraftAndLeavesTheCurrentPageUntouched() {
        let draft = PageContent(index: 0, text: "The dinosaur found a friend.", artPrompt: "a dinosaur and a bird")
        let response = StoryTurnResponse(
            action: .newPage,
            page: StoryTurnPageResult(index: 1, text: "They went looking for berries.", artPrompt: "a forest path", breakSuggested: false),
            bible: .empty, parentNote: nil, timings: timings()
        )

        let outcome = StoryEngine.apply(response, to: book(), currentDraft: draft)

        #expect(outcome.currentDraft == draft)
        #expect(outcome.pendingNextDraft?.index == 1)
        #expect(outcome.pendingNextDraft?.text == "They went looking for berries.")
        #expect(outcome.pendingNextDraft?.version == 1)
    }

    @Test func reviseCurrentBumpsTheVersionAndDropsStaleMedia() {
        let draft = PageContent(
            index: 2, version: 1, text: "A dragon appears.", artPrompt: "a dragon",
            stillPath: "u/b/p2.png", motion: MotionParts(scene: "a cave", motion: "embers drift")
        )
        let response = StoryTurnResponse(
            action: .reviseCurrent,
            page: StoryTurnPageResult(index: 2, text: "A gentle dragon appears.", artPrompt: "a friendly dragon", breakSuggested: false),
            bible: .empty, parentNote: nil, timings: timings()
        )

        let outcome = StoryEngine.apply(response, to: book(), currentDraft: draft)

        #expect(outcome.currentDraft.version == 2)
        #expect(outcome.currentDraft.text == "A gentle dragon appears.")
        #expect(outcome.currentDraft.artPrompt == "a friendly dragon")
        #expect(outcome.currentDraft.stillPath == nil)
        #expect(outcome.currentDraft.motion == nil)
        #expect(outcome.pendingNextDraft == nil)
    }

    @Test func noneSurfacesTheParentNoteAndChangesNothingElse() {
        let draft = PageContent(index: 0, text: "Once upon a time", artPrompt: "a meadow")
        let response = StoryTurnResponse(action: .none, page: nil, bible: .empty, parentNote: "Let's try a gentler idea.", timings: timings())

        let outcome = StoryEngine.apply(response, to: book(), currentDraft: draft)

        #expect(outcome.currentDraft == draft)
        #expect(outcome.pendingNextDraft == nil)
        #expect(outcome.parentNote == "Let's try a gentler idea.")
    }

    @Test func aMissingPageOnAnActionThatNeedsOneLeavesEverythingUnchanged() {
        let draft = PageContent(index: 0, text: "Once upon a time", artPrompt: "a meadow")
        let response = StoryTurnResponse(action: .append, page: nil, bible: .empty, parentNote: nil, timings: timings())

        let outcome = StoryEngine.apply(response, to: book(), currentDraft: draft)

        #expect(outcome.currentDraft == draft)
        #expect(outcome.pendingNextDraft == nil)
    }

    // MARK: - request building

    @Test func turnRequestCarriesTheBookBriefBibleAndDraftWithTheGivenInput() {
        let existingPage = PageContent(index: 0, text: "Once upon a time")
        let draft = PageContent(index: 1, text: "so far, so good")
        let bible = StoryBible(setting: "a meadow", directions: ["add a dragon"])
        let input = StoryTurnInput(kind: .speech, speaker: .kid, text: "make it fly")

        let request = StoryEngine.turnRequest(book: book(pages: [existingPage], bible: bible), kid: kid, settings: settings, currentDraft: draft, input: input)

        #expect(request.mode == .turn)
        #expect(request.kid == StoryTurnKid(kid))
        #expect(request.brief == StoryBrief(interests: ["dinosaurs"], teach: "sharing"))
        #expect(request.settings == settings)
        #expect(request.bible == bible)
        #expect(request.pages == [StoryTurnPageRef(index: 0, text: "Once upon a time")])
        #expect(request.current == StoryTurnCurrent(index: 1, text: "so far, so good"))
        #expect(request.input == input)
    }

    @Test func titleRequestOmitsCurrentAndInputAndUsesEveryFinishedPage() {
        let pages = [PageContent(index: 0, text: "Once upon a time"), PageContent(index: 1, text: "The end.")]
        let request = StoryEngine.titleRequest(book: book(pages: pages), kid: kid, settings: settings)

        #expect(request.mode == .title)
        #expect(request.current == nil)
        #expect(request.input == nil)
        #expect(request.pages.map(\.text) == ["Once upon a time", "The end."])
    }

    @Test func continueInputBuildsAContinueKindWithNoText() {
        let input = StoryEngine.continueInput(speaker: .parent)
        #expect(input.kind == .continueStory)
        #expect(input.speaker == .parent)
        #expect(input.text.isEmpty)
    }

    // MARK: - reading-level validation

    @Test func wordCountIgnoresExtraWhitespace() {
        #expect(StoryEngine.wordCount("  Once   upon\na time ") == 4)
        #expect(StoryEngine.wordCount("") == 0)
    }

    @Test func exceedsReadingLevelComparesAgainstEachLevelsMaxWords() {
        let fifteenWords = Array(repeating: "hop", count: 15).joined(separator: " ")
        let sixteenWords = Array(repeating: "hop", count: 16).joined(separator: " ")
        #expect(StoryEngine.exceedsReadingLevel(fifteenWords, level: .listener) == false)
        #expect(StoryEngine.exceedsReadingLevel(sixteenWords, level: .listener) == true)

        let thirtyWords = Array(repeating: "hop", count: 30).joined(separator: " ")
        #expect(StoryEngine.exceedsReadingLevel(thirtyWords, level: .earlyReader) == false)

        let sixtyOneWords = Array(repeating: "hop", count: 61).joined(separator: " ")
        #expect(StoryEngine.exceedsReadingLevel(sixtyOneWords, level: .reader) == true)
    }
}
