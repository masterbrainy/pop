import Foundation
import Observation
import PopKit

/// App-wide state: the kid profile, parent settings, and the bookshelf. Finished books are
/// saved on the device with their pictures and clips (`FileBookStore`), so they show exactly
/// as made and work offline (PRD P-01, ROADMAP Phase 5).
@MainActor
@Observable
final class AppModel {
    private(set) var kid: KidProfile
    private(set) var settings: ParentSettings
    private(set) var books: [Book] = []
    private(set) var loadError: String?

    @ObservationIgnored private let store: FileBookStore?
    @ObservationIgnored private let root = URL.applicationSupportDirectory.appending(path: "books", directoryHint: .isDirectory)

    init() {
        kid = Self.loadValue(KidProfile.self, key: Self.kidKey) ?? SampleBooks.kid
        settings = Self.loadValue(ParentSettings.self, key: Self.settingsKey) ?? ParentSettings()
        store = try? FileBookStore(root: root)
    }

    /// Loads saved books, newest first, with the sample book at the end of the shelf.
    func load() async {
        guard let store else {
            books = [SampleBooks.fox]
            return
        }
        do {
            let shelf = try await store.loadShelf()
            books = shelf.books.map(resolvingPaths) + [SampleBooks.fox]
            loadError = shelf.unreadableCount > 0 ? "Some saved books couldn't be opened." : nil
        } catch {
            loadError = "Some saved books couldn't be opened."
            books = [SampleBooks.fox]
        }
    }

    func newBook(brief: StoryBrief) -> Book {
        Book(kidId: kid.id, brief: brief, createdAt: .now)
    }

    /// Saves a finished (or partly told) book and puts it on the shelf.
    func save(_ book: Book) async {
        guard book.id != SampleBooks.fox.id, let store else { return }
        do {
            let saved = resolvingPaths(try await store.save(book))
            books = [saved] + books.filter { $0.id != saved.id }
        } catch {
            loadError = "The book couldn't be saved: \(error.localizedDescription)"
        }
    }

    func delete(_ book: Book) async {
        guard book.id != SampleBooks.fox.id else { return }
        do {
            try await store?.delete(book.id)
            books.removeAll { $0.id == book.id }
        } catch {
            loadError = "The book couldn't be deleted: \(error.localizedDescription)"
        }
    }

    func update(kid: KidProfile, settings: ParentSettings) {
        self.kid = kid
        self.settings = settings
        Self.saveValue(kid, key: Self.kidKey)
        Self.saveValue(settings, key: Self.settingsKey)
    }

    /// `FileBookStore` keeps `file:<name>` paths relative to the book's folder; the views
    /// read absolute paths.
    private func resolvingPaths(_ book: Book) -> Book {
        let media = root.appending(path: book.id.uuidString).appending(path: "media")
        func absolute(_ path: String?) -> String? {
            guard let path, path.hasPrefix("file:") else { return path }
            return media.appending(path: String(path.dropFirst(5))).path(percentEncoded: false)
        }
        let pages = book.pages.map { page in
            let layers = page.layers.map { layers in
                PageLayers(platePath: absolute(layers.platePath) ?? layers.platePath,
                           cutouts: layers.cutouts.map { Cutout(characterId: $0.characterId, path: absolute($0.path) ?? $0.path) })
            }
            return PageContent(id: page.id, index: page.index, version: page.version, text: page.text, artPrompt: page.artPrompt,
                               stillPath: absolute(page.stillPath), layers: layers, motion: page.motion, clipPath: absolute(page.clipPath),
                               question: page.question)
        }
        return Book(id: book.id, kidId: book.kidId, brief: book.brief, bible: book.bible, pages: pages, status: book.status,
                    title: book.title, coverPath: absolute(book.coverPath), createdAt: book.createdAt, finishedAt: book.finishedAt)
    }

    private static let kidKey = "kidProfile"
    private static let settingsKey = "parentSettings"

    private static func loadValue<T: Decodable>(_ type: T.Type, key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private static func saveValue<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }
}
