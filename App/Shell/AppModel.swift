import Foundation
import Observation
import PopKit

/// App-wide state: the kid profile and the bookshelf. Books are sample data until
/// `BookStore` arrives in Phase 5.
@MainActor
@Observable
final class AppModel {
    private(set) var kid = SampleBooks.kid
    private(set) var books = [SampleBooks.fox]

    func book(withId id: Book.ID) -> Book? {
        books.first { $0.id == id }
    }

    /// Starts an empty book to be told (the brief and live generation arrive in Phase 2).
    func newBook() -> Book {
        let book = Book(kidId: kid.id, brief: StoryBrief(interests: kid.interests), createdAt: .now)
        books = [book] + books
        return book
    }
}
