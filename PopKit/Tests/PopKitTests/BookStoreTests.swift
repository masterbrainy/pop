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
}
