import Foundation
import Observation
import PopKit

/// The book being read or made: which page shows, and what posture events do to it.
@MainActor
@Observable
final class BookReader {
    private(set) var book: Book
    private(set) var navigator: BookNavigator
    /// Set when the phone stays closed past the hold; Phase 5 finishes and saves here.
    private(set) var closedAt: Date?

    init(book: Book, mode: BookMode) {
        self.book = book
        navigator = BookNavigator(pageCount: book.pages.count, mode: mode)
    }

    var currentPage: PageContent? {
        book.pages.indices.contains(navigator.index) ? book.pages[navigator.index] : nil
    }

    var pageNumber: Int { navigator.index + 1 }

    func handle(_ event: PostureEvent) {
        switch event {
        case .turnCommitted: turnForward()
        case .opened: navigator = navigator.openedFromCover()
        case .closed: closedAt = .now
        case .pageSettled, .turnCancelled, .popBegan, .popEnded: break
        }
    }

    func turnForward() {
        let (next, outcome) = navigator.turningForward()
        navigator = next
        if case let .newPage(index) = outcome {
            book = book.with(pages: book.pages + [PageContent(index: index, text: "")])
        }
    }

    func turnBack() {
        navigator = navigator.turningBack()
    }
}
