import Foundation

/// The result of one `path` or `page` call (P-04): the book with its (re-)planned path,
/// the page it wrote, and a gentle note for the parent when nothing was written.
public struct PathOutcome: Sendable, Equatable {
    public let book: Book
    public let page: PageContent?
    public let parentNote: String?

    public init(book: Book, page: PageContent?, parentNote: String?) {
        self.book = book
        self.page = page
        self.parentNote = parentNote
    }
}

/// Pure story-path reducer and request builder (P-04). Talking to the `story-turn`
/// function itself is `PopServer`'s job; this only turns its response into new state
/// and turns a book's current state into its next `path`/`page`/`title` request.
public enum StoryEngine {
    /// Applies a `path` or `page` response. The page on screen is never touched: the written
    /// page is new, for the index the request asked for. A refused turn leaves the book as it was.
    public static func applyPage(_ response: StoryTurnResponse, to book: Book) -> PathOutcome {
        guard response.action != .none else {
            return PathOutcome(book: book, page: nil, parentNote: response.parentNote)
        }
        let updatedBook = book.with(bible: response.bible.carryingReferences(from: book.bible))
        let page = response.page.map {
            PageContent(index: $0.index, text: $0.text, artPrompt: $0.artPrompt).with(question: $0.question)
        }
        return PathOutcome(book: updatedBook, page: page, parentNote: response.parentNote)
    }

    /// A `mode: "path"` request: plan the story from the brief (index 0, no input), or re-plan
    /// it from `index` following a direction. `shownPages` are the pages the reader has seen.
    public static func pathRequest(
        book: Book, kid: KidProfile, settings: ParentSettings, shownPages: [PageContent], index: Int, input: StoryTurnInput?
    ) -> StoryTurnRequest {
        request(.path, book: book, kid: kid, settings: settings, shownPages: shownPages, index: index, input: input)
    }

    /// A `mode: "page"` request: write page `index` along the existing path.
    public static func pageRequest(book: Book, kid: KidProfile, settings: ParentSettings, shownPages: [PageContent], index: Int) -> StoryTurnRequest {
        request(.page, book: book, kid: kid, settings: settings, shownPages: shownPages, index: index, input: nil)
    }

    private static func request(
        _ mode: StoryTurnMode, book: Book, kid: KidProfile, settings: ParentSettings, shownPages: [PageContent], index: Int, input: StoryTurnInput?
    ) -> StoryTurnRequest {
        StoryTurnRequest(
            mode: mode, bookId: book.id, kid: StoryTurnKid(kid), brief: book.brief, settings: settings, bible: book.bible,
            pages: shownPages.map(StoryTurnPageRef.init), input: input, index: index
        )
    }

    /// A `mode: "title"` request from the book's finished pages.
    public static func titleRequest(book: Book, kid: KidProfile, settings: ParentSettings) -> StoryTurnRequest {
        .title(bookId: book.id, kid: StoryTurnKid(kid), brief: book.brief, settings: settings, bible: book.bible, pages: book.pages.map(StoryTurnPageRef.init))
    }

    /// Words in `text`, split on whitespace and newlines (PRD §8.7).
    public static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// Whether `text` has more words than `level` allows on one page.
    public static func exceedsReadingLevel(_ text: String, level: ReadingLevel) -> Bool {
        wordCount(text) > level.maxWordsPerPage
    }
}
