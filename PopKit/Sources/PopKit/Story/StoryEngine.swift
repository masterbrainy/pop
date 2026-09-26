import Foundation

/// The result of applying one `story-turn` response to a book and the page currently
/// being drafted: an updated book (the bible always carries forward), the current
/// draft (replaced, revised, or untouched), a pending next-page draft shown only
/// after the parent folds, and a gentle note for the parent when there's nothing
/// to show (docs/CONTRACTS.md §3 `story-turn`).
public struct StoryTurnOutcome: Sendable, Equatable {
    public let book: Book
    public let currentDraft: PageContent
    /// Set only for `action: "new_page"`. The engine never turns the page itself;
    /// the app shows this once the parent folds (ROADMAP §2 Phase 2).
    public let pendingNextDraft: PageContent?
    public let parentNote: String?

    public init(book: Book, currentDraft: PageContent, pendingNextDraft: PageContent?, parentNote: String?) {
        self.book = book
        self.currentDraft = currentDraft
        self.pendingNextDraft = pendingNextDraft
        self.parentNote = parentNote
    }
}

/// Pure story-turn reducer and request builder. Talking to the `story-turn` function
/// itself is `PopServer`'s job; this only turns its response into new state and
/// turns a book's current state into its next request.
public enum StoryEngine {
    /// Applies one `story-turn` response. `page` may be `nil` only for `action: .none`;
    /// if a `page`-requiring action arrives without one, the draft is left unchanged
    /// rather than guessed at.
    public static func apply(_ response: StoryTurnResponse, to book: Book, currentDraft: PageContent) -> StoryTurnOutcome {
        let updatedBook = book.with(bible: response.bible)

        switch (response.action, response.page) {
        case (.none, _):
            return StoryTurnOutcome(book: updatedBook, currentDraft: currentDraft, pendingNextDraft: nil, parentNote: response.parentNote)

        case let (.append, .some(page)):
            let updated = replacing(currentDraft, text: page.text, artPrompt: page.artPrompt)
            return StoryTurnOutcome(book: updatedBook, currentDraft: updated, pendingNextDraft: nil, parentNote: nil)

        case let (.reviseCurrent, .some(page)):
            let revised = currentDraft.revised(text: page.text, artPrompt: page.artPrompt)
            return StoryTurnOutcome(book: updatedBook, currentDraft: revised, pendingNextDraft: nil, parentNote: nil)

        case let (.newPage, .some(page)) where currentDraft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            // Nothing to turn away from yet: the words belong on this page.
            let filled = replacing(currentDraft, text: page.text, artPrompt: page.artPrompt)
            return StoryTurnOutcome(book: updatedBook, currentDraft: filled, pendingNextDraft: nil, parentNote: nil)

        case let (.newPage, .some(page)):
            let pending = PageContent(index: page.index, text: page.text, artPrompt: page.artPrompt)
            return StoryTurnOutcome(book: updatedBook, currentDraft: currentDraft, pendingNextDraft: pending, parentNote: nil)

        case (.append, .none), (.reviseCurrent, .none), (.newPage, .none):
            return StoryTurnOutcome(book: updatedBook, currentDraft: currentDraft, pendingNextDraft: nil, parentNote: nil)
        }
    }

    /// A `mode: "turn"` request from the book's current state, its brief and bible,
    /// the kid, the parent's settings, the draft in progress, and this turn's input.
    public static func turnRequest(book: Book, kid: KidProfile, settings: ParentSettings, currentDraft: PageContent, input: StoryTurnInput) -> StoryTurnRequest {
        .turn(
            bookId: book.id, kid: StoryTurnKid(kid), brief: book.brief, settings: settings, bible: book.bible,
            pages: book.pages.map(StoryTurnPageRef.init),
            current: StoryTurnCurrent(index: currentDraft.index, text: currentDraft.text), input: input
        )
    }

    /// A `mode: "title"` request from the book's finished pages.
    public static func titleRequest(book: Book, kid: KidProfile, settings: ParentSettings) -> StoryTurnRequest {
        .title(bookId: book.id, kid: StoryTurnKid(kid), brief: book.brief, settings: settings, bible: book.bible, pages: book.pages.map(StoryTurnPageRef.init))
    }

    /// The input for a "You continue" tap (ROADMAP §2 Phase 2): no words of its own.
    public static func continueInput(speaker: Speaker) -> StoryTurnInput {
        StoryTurnInput(kind: .continueStory, speaker: speaker, text: "")
    }

    /// Words in `text`, split on whitespace and newlines (PRD §8.7).
    public static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// Whether `text` has more words than `level` allows on one page.
    public static func exceedsReadingLevel(_ text: String, level: ReadingLevel) -> Bool {
        wordCount(text) > level.maxWordsPerPage
    }

    private static func replacing(_ page: PageContent, text: String, artPrompt: String?) -> PageContent {
        PageContent(
            id: page.id, index: page.index, version: page.version, text: text, artPrompt: artPrompt,
            stillPath: page.stillPath, layers: page.layers, motion: page.motion, clipPath: page.clipPath
        )
    }
}
