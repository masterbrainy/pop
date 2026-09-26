import Foundation
import Testing
@testable import PopKit

/// Covers `FileBookStore`: saving a finished book copies its media next to a
/// `book.json` and rewrites each path to a relative `file:` reference, `loadAll`
/// reloads every saved book sorted newest first, and a saved book round-trips
/// identically through save → load (ROADMAP §2 `BookStore`).
struct BookStoreTests {
    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BookStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Writes a source "media file" outside the store, for `save` to copy in.
    private func writeSourceFile(_ bytes: [UInt8], name: String, in directory: URL) throws -> String {
        let url = directory.appendingPathComponent(name)
        try Data(bytes).write(to: url)
        return url.path
    }

    private func book(id: UUID = UUID(), createdAt: Date, coverPath: String?, pages: [PageContent]) -> Book {
        Book(id: id, kidId: UUID(), brief: StoryBrief(interests: ["dinosaurs"]), pages: pages, coverPath: coverPath, createdAt: createdAt)
    }

    @Test func saveCopiesMediaAndRewritesEveryPathToARelativeFileReference() async throws {
        let sources = try makeTempDirectory()
        let root = try makeTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: sources)
            try? FileManager.default.removeItem(at: root)
        }
        let store = try FileBookStore(root: root)

        let coverSource = try writeSourceFile([0xC0, 0xFF, 0xEE], name: "cover-source.png", in: sources)
        let stillSource = try writeSourceFile([0x01], name: "p0-source.png", in: sources)
        let plateSource = try writeSourceFile([0x02], name: "p0-plate-source.png", in: sources)
        let cutoutSource = try writeSourceFile([0x03], name: "p0-fox-source.png", in: sources)
        let clipSource = try writeSourceFile([0x04], name: "p0-clip-source.mp4", in: sources)

        let page = PageContent(
            index: 0, text: "Once upon a time", stillPath: stillSource,
            layers: PageLayers(platePath: plateSource, cutouts: [Cutout(characterId: "fox", path: cutoutSource)]),
            clipPath: clipSource
        )
        let original = book(createdAt: Date(timeIntervalSince1970: 0), coverPath: coverSource, pages: [page])

        let saved = try await store.save(original)

        #expect(saved.coverPath == "file:cover.png")
        #expect(saved.pages[0].stillPath == "file:page-0-v1.png")
        #expect(saved.pages[0].layers?.platePath == "file:page-0-v1-plate.png")
        #expect(saved.pages[0].layers?.cutouts.first?.path == "file:page-0-v1-cutout-fox.png")
        #expect(saved.pages[0].clipPath == "file:page-0-v1-clip.mp4")

        // the bytes were actually copied, not just referenced.
        let resolvedCover = try #require(await store.resolvedURL(for: saved.coverPath!, bookId: original.id))
        #expect(try Data(contentsOf: resolvedCover) == Data([0xC0, 0xFF, 0xEE]))
    }

    @Test func aSavedBookReloadsIdenticallyThroughLoadAll() async throws {
        let sources = try makeTempDirectory()
        let root = try makeTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: sources)
            try? FileManager.default.removeItem(at: root)
        }
        let store = try FileBookStore(root: root)

        let stillSource = try writeSourceFile([0x01, 0x02], name: "still.png", in: sources)
        let page = PageContent(index: 0, text: "Once upon a time", stillPath: stillSource)
        let original = book(createdAt: Date(timeIntervalSince1970: 12_345), coverPath: nil, pages: [page])

        let saved = try await store.save(original)
        let reloaded = try await store.loadAll()

        #expect(reloaded == [saved])
    }

    @Test func savingKeepsEachPagesReadingQuestion() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try FileBookStore(root: root)
        let page = PageContent(index: 0, text: "Pip swims.", question: "Where does Pip swim?")
        let saved = try await store.save(book(createdAt: Date(timeIntervalSince1970: 1), coverPath: nil, pages: [page]))
        #expect(saved.pages.first?.question == "Where does Pip swim?")
        #expect(try await store.loadAll().first?.pages.first?.question == "Where does Pip swim?")
    }

    @Test func loadAllSortsBooksNewestFirst() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try FileBookStore(root: root)

        let older = try await store.save(book(createdAt: Date(timeIntervalSince1970: 100), coverPath: nil, pages: []))
        let newer = try await store.save(book(createdAt: Date(timeIntervalSince1970: 200), coverPath: nil, pages: []))
        let newest = try await store.save(book(createdAt: Date(timeIntervalSince1970: 300), coverPath: nil, pages: []))

        let all = try await store.loadAll()
        #expect(all.map { $0.id } == [newest.id, newer.id, older.id])
    }

    @Test func deleteRemovesTheBookSoItNoLongerLoads() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try FileBookStore(root: root)

        let saved = try await store.save(book(createdAt: Date(), coverPath: nil, pages: []))
        #expect(try await store.loadAll().count == 1)

        try await store.delete(saved.id)

        #expect(try await store.loadAll().isEmpty)
    }

    @Test func loadAllOnAnEmptyStoreReturnsAnEmptyArray() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try FileBookStore(root: root)

        #expect(try await store.loadAll().isEmpty)
    }

    // MARK: - IMP-23: re-saving a reopened book

    /// The app reopens a saved book with every `file:` path resolved to the store's own
    /// absolute file (`AppModel.resolvingPaths`), so a second save copies each file onto itself.
    private func resolvedLikeTheApp(_ book: Book, store: FileBookStore) async -> Book {
        let absolute: @Sendable (String?) async -> String? = { path in
            guard let path else { return nil }
            return await store.resolvedURL(for: path, bookId: book.id)?.path ?? path
        }
        var pages: [PageContent] = []
        for page in book.pages {
            var layers: PageLayers?
            if let pageLayers = page.layers {
                var cutouts: [Cutout] = []
                for cutout in pageLayers.cutouts {
                    cutouts.append(Cutout(characterId: cutout.characterId, path: await absolute(cutout.path) ?? cutout.path))
                }
                layers = PageLayers(platePath: await absolute(pageLayers.platePath) ?? pageLayers.platePath, cutouts: cutouts)
            }
            pages.append(PageContent(
                id: page.id, index: page.index, version: page.version, text: page.text, artPrompt: page.artPrompt,
                stillPath: await absolute(page.stillPath), layers: layers, motion: page.motion,
                clipPath: await absolute(page.clipPath), question: page.question
            ))
        }
        return Book(id: book.id, kidId: book.kidId, brief: book.brief, bible: book.bible, pages: pages, status: book.status,
                    title: book.title, coverPath: await absolute(book.coverPath), createdAt: book.createdAt, finishedAt: book.finishedAt)
    }

    private func mediaPaths(of book: Book) -> [String] {
        var paths = [book.coverPath].compactMap { $0 }
        for page in book.pages {
            paths += [page.stillPath, page.clipPath, page.layers?.platePath].compactMap { $0 }
            paths += page.layers?.cutouts.map(\.path) ?? []
        }
        return paths
    }

    @Test func saveLoadSaveKeepsEveryMediaFileAndItsBytes() async throws {
        let sources = try makeTempDirectory()
        let root = try makeTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: sources)
            try? FileManager.default.removeItem(at: root)
        }
        let store = try FileBookStore(root: root)
        let page = PageContent(
            index: 0, text: "Once upon a time",
            stillPath: try writeSourceFile([0x01], name: "still.png", in: sources),
            layers: PageLayers(platePath: try writeSourceFile([0x02], name: "plate.png", in: sources),
                               cutouts: [Cutout(characterId: "fox", path: try writeSourceFile([0x03], name: "fox.png", in: sources))]),
            clipPath: try writeSourceFile([0x04], name: "clip.mp4", in: sources)
        )
        let cover = try writeSourceFile([0x05], name: "cover.png", in: sources)
        let original = book(createdAt: Date(timeIntervalSince1970: 1), coverPath: cover, pages: [page])
        _ = try await store.save(original)

        let loaded = try #require(try await store.loadAll().first)
        let reopened = await resolvedLikeTheApp(loaded, store: store)
        let resaved = try await store.save(reopened)

        #expect(resaved == (try await store.loadAll().first))
        let expected: [String: UInt8] = [
            "file:cover.png": 0x05, "file:page-0-v1.png": 0x01, "file:page-0-v1-plate.png": 0x02,
            "file:page-0-v1-cutout-fox.png": 0x03, "file:page-0-v1-clip.mp4": 0x04,
        ]
        #expect(Set(mediaPaths(of: resaved)) == Set(expected.keys))
        for (path, byte) in expected {
            let url = try #require(await store.resolvedURL(for: path, bookId: original.id))
            #expect((try? Data(contentsOf: url)) == Data([byte]), "\(path) was lost on re-save")
        }
    }

    @Test func resavingABookWhosePathsAreStillRelativeFileReferencesKeepsItsMedia() async throws {
        let sources = try makeTempDirectory()
        let root = try makeTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: sources)
            try? FileManager.default.removeItem(at: root)
        }
        let store = try FileBookStore(root: root)
        let still = try writeSourceFile([0x09], name: "still.png", in: sources)
        let page = PageContent(index: 0, text: "Pip swims.", stillPath: still)
        let saved = try await store.save(book(createdAt: Date(timeIntervalSince1970: 1), coverPath: nil, pages: [page]))

        let resaved = try await store.save(saved)

        let stillPath = try #require(resaved.pages.first?.stillPath)
        let url = try #require(await store.resolvedURL(for: stillPath, bookId: saved.id))
        #expect((try? Data(contentsOf: url)) == Data([0x09]))
    }

    @Test func aCorruptBookIsSkippedAndTheGoodOnesStillLoad() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try FileBookStore(root: root)
        let good1 = try await store.save(book(createdAt: Date(timeIntervalSince1970: 100), coverPath: nil, pages: []))
        let good2 = try await store.save(book(createdAt: Date(timeIntervalSince1970: 200), coverPath: nil, pages: []))
        let corruptDirectory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: corruptDirectory, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: corruptDirectory.appendingPathComponent("book.json"))

        let shelf = try await store.loadShelf()

        #expect(shelf.books.map(\.id) == [good2.id, good1.id])
        #expect(shelf.unreadableCount == 1)
        #expect(try await store.loadAll().map(\.id) == [good2.id, good1.id])
    }
}
