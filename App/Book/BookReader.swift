import Foundation
import Observation
import PopKit

/// The book being read or made: which page shows, and what posture events do to it.
/// While creating, the story pipeline updates pages through `update(book:)` and
/// `replace(_:)`, and a folded-to page takes the engine's pending draft if there is one.
@MainActor
@Observable
final class BookReader {
    private(set) var book: Book
    private(set) var navigator: BookNavigator
    /// Set when the phone stays closed past the hold; the book finishes and saves then (Phase 5).
    private(set) var closedAt: Date?
    /// The next page's draft from a `new_page` turn; it appears when the parent folds (PRD S4).
    var pendingNext: PageContent?
    /// How deep the page now showing pops up (0…1), from the posture machine.
    private(set) var popDepth: Double = 0

    @ObservationIgnored var onPageChange: @MainActor (PageContent?) -> Void = { _ in }
    @ObservationIgnored var onClosedHold: @MainActor () -> Void = {}

    init(book: Book, mode: BookMode) {
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
            // A page only follows one that has words; an empty page stays put.
            guard !(currentPage?.text.isEmpty ?? true) else { return }
            let page = pendingNext.map { $0.index == index ? $0 : PageContent(index: index, text: $0.text, artPrompt: $0.artPrompt, stillPath: $0.stillPath) }
                ?? PageContent(index: index, text: "")
            pendingNext = nil
            book = book.with(pages: book.pages + [page])
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

    /// Takes the pipeline's book (bible and pages) while keeping pages the reader added since.
    func update(book updated: Book) {
        let extra = book.pages.filter { page in !updated.pages.contains { $0.index == page.index } }
        book = updated.with(pages: (updated.pages + extra).sorted { $0.index < $1.index })
        navigator = navigator.with(pageCount: book.pages.count)
    }

    /// Replaces the page with the same index (a newer draft, a picture, a clip).
    func replace(_ page: PageContent) {
        if pendingNext?.index == page.index {
            pendingNext = page
            return
        }
        guard let position = book.pages.firstIndex(where: { $0.index == page.index }) else { return }
        var pages = book.pages
        pages[position] = page
        book = book.with(pages: pages)
    }

    /// Changes the page with this index, whether it's in the book or the pending draft.
    func updatePage(index: Int, _ change: (PageContent) -> PageContent) {
        if let pending = pendingNext, pending.index == index {
            pendingNext = change(pending)
        } else if let page = book.pages.first(where: { $0.index == index }) {
            replace(change(page))
        }
    }

    func page(id: UUID) -> PageContent? {
        book.pages.first { $0.id == id } ?? (pendingNext?.id == id ? pendingNext : nil)
    }

    func finish(title: String, coverPath: String?) {
        let written = book.pages.filter { !$0.text.isEmpty }
        book = book.with(pages: written).finished(title: title, coverPath: coverPath, at: .now)
        navigator = BookNavigator(pageCount: book.pages.count, mode: .reading)
    }
}
