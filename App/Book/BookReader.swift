import Foundation
import Observation
import PopKit

/// The book being read or made: which page shows, and what posture events do to it.
/// While creating, the story pipeline places written pages with `place(_:)`, changes pages by
/// id and version with `updatePage(id:version:_:)`, and changes the bible with `updateStory(_:)`,
/// always on the latest copy; a folded-to page takes the page built behind if there is one.
/// Up to `lookahead` pages are built ahead of the one on screen.
@MainActor
@Observable
final class BookReader {
    private(set) var book: Book
    private(set) var navigator: BookNavigator
    /// Set when the phone stays closed past the hold; the book finishes and saves then (Phase 5).
    private(set) var closedAt: Date?
    /// The pages built ahead of the one on screen, in order (P-04); the first appears when the
    /// parent folds.
    private(set) var ahead: [PageContent] = []
    /// How many pages are built ahead of the one on screen.
    let lookahead: Int
    /// How deep the page now showing pops up (0…1), from the posture machine.
    private(set) var popDepth: Double = 0

    @ObservationIgnored var onPageChange: @MainActor (PageContent?) -> Void = { _ in }
    @ObservationIgnored var onClosedHold: @MainActor () -> Void = {}
    /// A turn while creating, before the page behind has its words: nothing turns.
    @ObservationIgnored var onTurnBlocked: @MainActor () -> Void = {}
    /// While creating, whether the page behind (which has its words) may open yet; the story
    /// maker holds it back until its picture is ready.
    @ObservationIgnored var canOpenPendingNext: @MainActor (PageContent) -> Bool = { _ in true }

    /// The page built behind the one on screen; it appears when the parent folds.
    var pendingNext: PageContent? { ahead.first }

    init(book: Book, mode: BookMode, lookahead: Int = 2) {
        self.lookahead = lookahead
        let starting = mode == .creating && book.pages.isEmpty ? book.with(pages: [PageContent(index: 0, text: "")]) : book
        self.book = starting
        navigator = BookNavigator(pageCount: starting.pages.count, mode: mode)
    }

    var currentPage: PageContent? {
        book.pages.indices.contains(navigator.index) ? book.pages[navigator.index] : nil
    }

    var pageNumber: Int { navigator.index + 1 }
    var isCreating: Bool { navigator.mode == .creating }

    func handle(_ event: PostureEvent) {
        switch event {
        case .turnCommitted: turnForward()
        case .opened:
            closedAt = nil
            navigator = navigator.openedFromCover()
            onPageChange(currentPage)
        case .closed:
            closedAt = .now
            onClosedHold()
        case .pageSettled, .turnCancelled, .popBegan, .popEnded: break
        }
    }

    func setPopDepth(_ depth: Double) {
        if abs(depth - popDepth) > 0.005 { popDepth = depth }
    }

    func turnForward() {
        let (next, outcome) = navigator.turningForward()
        if case let .newPage(index) = outcome {
            // A page only follows one that has words, and nothing follows the story's ending.
            guard let current = currentPage, !current.text.isEmpty, !book.bible.isEnding(pageIndex: current.index) else { return }
            // The next page opens only once it has its words and its picture.
            guard let pending = pendingNext, !pending.text.isEmpty, canOpenPendingNext(pending) else {
                onTurnBlocked()
                return
            }
            if pending.index == index, let turned = draft.turning() {
                book = book.with(pages: turned.pages)
                ahead = turned.ahead
            } else {
                // Out of step (shouldn't happen): keep the words, and rebuild what's ahead.
                let page = PageContent(index: index, text: pending.text, artPrompt: pending.artPrompt, stillPath: pending.stillPath, question: pending.question)
                ahead = []
                book = book.with(pages: book.pages + [page])
            }
            navigator = next.with(pageCount: book.pages.count)
        } else {
            navigator = next
        }
        onPageChange(currentPage)
    }

    func turnBack() {
        navigator = navigator.turningBack()
        onPageChange(currentPage)
    }

    /// Changes the story (bible, brief) on the current book; pages always stay the reader's.
    func updateStory(_ change: (Book) -> Book) {
        book = change(book).with(pages: book.pages)
    }

    /// Places a page the story engine just wrote: an empty page on screen takes it, else it
    /// becomes the page behind. A page the reader has seen never changes.
    func place(_ written: PageContent) -> PagePlacement {
        let (next, placement) = draft.placing(written, currentIndex: currentPage?.index, lookahead: lookahead)
        adopt(next)
        return placement
    }

    /// Changes the page with this id (and version, when given), in the book or behind it.
    /// Returns the changed page, or nil if it was replaced meanwhile.
    @discardableResult
    func updatePage(id: UUID, version: Int? = nil, _ change: (PageContent) -> PageContent) -> PageContent? {
        guard let (next, page) = draft.updatingPage(id: id, version: version, change) else { return nil }
        adopt(next)
        return page
    }

    func page(id: UUID) -> PageContent? {
        draft.page(id: id)
    }

    private var draft: DraftPages { DraftPages(pages: book.pages, ahead: ahead) }

    private func adopt(_ next: DraftPages) {
        if next.pages != book.pages {
            book = book.with(pages: next.pages)
            navigator = navigator.with(pageCount: book.pages.count)
        }
        if next.ahead != ahead { ahead = next.ahead }
    }

    func finish(title: String, coverPath: String?) {
        let written = book.pages.filter { !$0.text.isEmpty }
        book = book.with(pages: written).finished(title: title, coverPath: coverPath, at: .now)
        navigator = BookNavigator(pageCount: book.pages.count, mode: .reading)
    }
}
