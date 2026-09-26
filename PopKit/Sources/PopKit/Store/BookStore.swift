import Foundation

/// Where a finished book is persisted, so the app can swap a Supabase-backed
/// implementation in later without changing anything that calls it
/// (ROADMAP §2 `BookStore`).
public protocol BookStoring: Sendable {
    /// Copies the book's media into this store and returns the book with its paths
    /// rewritten to wherever the store actually put them.
    @discardableResult
    func save(_ book: Book) async throws -> Book

    /// Every saved book, newest first (`createdAt` descending) — the bookshelf order.
    func loadAll() async throws -> [Book]

    func delete(_ bookId: UUID) async throws
}

/// The result of reading the whole shelf: the books that loaded, and a count of the
/// ones that didn't, so the app can say "some books couldn't be opened" without losing the rest.
public struct BookShelfLoad: Sendable, Equatable {
    public let books: [Book]
    public let unreadableCount: Int

    public init(books: [Book], unreadableCount: Int) {
        self.books = books
        self.unreadableCount = unreadableCount
    }
}

/// Saves each book as `{root}/{bookId}/book.json` plus its media under
/// `{root}/{bookId}/media/`. Paths inside `book.json` are relative, `file:`-prefixed
/// references into that same `media/` folder (for example `file:cover.png`), so a
/// saved book is self-contained and survives the app's container path changing
/// between launches; `resolvedURL(for:bookId:)` turns one back into a real file URL.
public actor FileBookStore: BookStoring {
    private let root: URL
    private let fileManager: FileManager

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public init(root: URL, fileManager: FileManager = .default) throws {
        self.root = root
        self.fileManager = fileManager
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    public func save(_ book: Book) async throws -> Book {
        let bookDirectory = directory(for: book.id)
        let mediaDirectory = bookDirectory.appendingPathComponent("media", isDirectory: true)
        try fileManager.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)

        let coverPath = try book.coverPath.map { try copyMedia(from: $0, into: mediaDirectory, baseName: "cover") }
        let pages = try book.pages.map { try rewritten(page: $0, into: mediaDirectory) }
        let rewrittenBook = Book(
            id: book.id, kidId: book.kidId, brief: book.brief, bible: book.bible, pages: pages,
            status: book.status, title: book.title, coverPath: coverPath, createdAt: book.createdAt, finishedAt: book.finishedAt
        )

        let data = try Self.encoder.encode(rewrittenBook)
        try data.write(to: bookDirectory.appendingPathComponent("book.json"), options: .atomic)
        return rewrittenBook
    }

    public func loadAll() async throws -> [Book] {
        try await loadShelf().books
    }

    /// Every readable saved book, newest first, plus how many `book.json` files couldn't
    /// be read or decoded. One corrupt book is skipped rather than hiding the whole shelf.
    public func loadShelf() async throws -> BookShelfLoad {
        guard fileManager.fileExists(atPath: root.path) else { return BookShelfLoad(books: [], unreadableCount: 0) }
        let entries = try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])

        var books: [Book] = []
        var unreadableCount = 0
        for directory in entries {
            let bookFile = directory.appendingPathComponent("book.json")
            guard fileManager.fileExists(atPath: bookFile.path) else { continue }
            do {
                let data = try Data(contentsOf: bookFile)
                books.append(try Self.decoder.decode(Book.self, from: data))
            } catch {
                unreadableCount += 1
            }
        }
        return BookShelfLoad(books: books.sorted { $0.createdAt > $1.createdAt }, unreadableCount: unreadableCount)
    }

    public func delete(_ bookId: UUID) async throws {
        let directory = directory(for: bookId)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    /// Resolves a `book.json` path like `"file:cover.png"` to the real file this
    /// store copied it to, or `nil` if it isn't one of this store's references.
    public func resolvedURL(for path: String, bookId: UUID) -> URL? {
        guard path.hasPrefix(Self.filePrefix) else { return nil }
        let filename = String(path.dropFirst(Self.filePrefix.count))
        return directory(for: bookId).appendingPathComponent("media").appendingPathComponent(filename)
    }

    // MARK: - copying and rewriting

    private static let filePrefix = "file:"

    private func directory(for bookId: UUID) -> URL {
        root.appendingPathComponent(bookId.uuidString, isDirectory: true)
    }

    private func rewritten(page: PageContent, into mediaDirectory: URL) throws -> PageContent {
        let baseName = "page-\(page.index)-v\(page.version)"
        let stillPath = try page.stillPath.map { try copyMedia(from: $0, into: mediaDirectory, baseName: baseName) }
        let layers = try page.layers.map { try rewritten(layers: $0, baseName: baseName, into: mediaDirectory) }
        let clipPath = try page.clipPath.map { try copyMedia(from: $0, into: mediaDirectory, baseName: "\(baseName)-clip") }
        // Only the media paths change; the words, question and choices are kept as they are.
        return page.with(stillPath: stillPath).with(layers: layers).with(clipPath: clipPath)
    }

    private func rewritten(layers: PageLayers, baseName: String, into mediaDirectory: URL) throws -> PageLayers {
        let platePath = try copyMedia(from: layers.platePath, into: mediaDirectory, baseName: "\(baseName)-plate")
        let cutouts = try layers.cutouts.map { cutout in
            Cutout(characterId: cutout.characterId, path: try copyMedia(from: cutout.path, into: mediaDirectory, baseName: "\(baseName)-cutout-\(cutout.characterId)"))
        }
        return PageLayers(platePath: platePath, cutouts: cutouts)
    }

    /// Copies the file at `sourcePath` (a local path or `file:` URL) into
    /// `mediaDirectory`, keeping its original extension, and returns the new
    /// relative `file:` reference.
    ///
    /// A reopened book points at this store's own files (either as `file:<name>` or as the
    /// resolved absolute path), so the source can already *be* the destination. Deleting
    /// the destination first would then delete the only copy (IMP-23), so that case is a no-op.
    private func copyMedia(from sourcePath: String, into mediaDirectory: URL, baseName: String) throws -> String {
        let sourceURL = Self.resolveLocalURL(sourcePath, mediaDirectory: mediaDirectory)
        let ext = sourceURL.pathExtension
        let filename = ext.isEmpty ? baseName : "\(baseName).\(ext)"
        let destinationURL = mediaDirectory.appendingPathComponent(filename)

        if Self.isSameFile(sourceURL, destinationURL) {
            return "\(Self.filePrefix)\(filename)"
        }
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return "\(Self.filePrefix)\(filename)"
    }

    private static func isSameFile(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.resolvingSymlinksInPath().path == rhs.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// `file:<name>` (no `//`) is this store's own relative reference into the book's
    /// `media/` folder; anything else is a real URL or an absolute path.
    private static func resolveLocalURL(_ path: String, mediaDirectory: URL) -> URL {
        if path.hasPrefix(filePrefix), !path.hasPrefix("\(filePrefix)//") {
            return mediaDirectory.appendingPathComponent(String(path.dropFirst(filePrefix.count)))
        }
        if let url = URL(string: path), url.scheme != nil {
            return url
        }
        return URL(fileURLWithPath: path)
    }
}
