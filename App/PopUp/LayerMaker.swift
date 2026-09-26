import CoreImage
import Foundation
import PopKit
import UIKit

/// Makes a page's pop-up layers (ROADMAP Phase 4): a background plate without the
/// characters, plus one cutout per character drawn on a flat backdrop and cut out here on the
/// device (Vision's background removal doesn't run in the Simulator, ROADMAP §3).
/// Layers are prepared in the background once a page has its picture.
enum LayerMaker {
    /// Up to this many characters stand up out of one page.
    static let maxCutouts = 2

    static func makeLayers(for page: PageContent, book: Book, server: any PopServer, media: MediaCache) async throws -> PageLayers {
        let characters = charactersOnPage(page, bible: book.bible)
        let scene = page.artPrompt ?? page.text
        let plateRequest = ArtRequest(bookId: book.id, kind: .plate, pageIndex: page.index, version: page.version,
                                      prompt: scene, characters: book.bible.characters)
        async let plate = server.art(plateRequest)
        let cutouts = try await withThrowingTaskGroup(of: (Int, Cutout?).self) { group in
            for (slot, character) in characters.enumerated() {
                group.addTask {
                    let prompt = character.map { "\($0.name): \($0.description). Pose as in: \(scene)" } ?? "The main character of this scene: \(scene)"
                    let request = ArtRequest(bookId: book.id, kind: .cutout, pageIndex: page.index, version: page.version,
                                             prompt: prompt, characters: book.bible.characters, characterId: character?.id)
                    let art = try await server.art(request)
                    guard !art.placeholder, let url = URL(string: art.url) else { return (slot, nil) }
                    let name = "\(book.id)-p\(page.index)-v\(page.version)-cut\(slot)"
                    let raw = try await media.store(from: url, named: "\(name)-raw.png")
                    guard let keyed = keyedPNG(from: raw) else { return (slot, nil) }
                    let path = try await media.write(keyed, named: "\(name).png")
                    return (slot, Cutout(characterId: character?.id ?? "main", path: path))
                }
            }
            var found: [(Int, Cutout)] = []
            for try await (slot, cutout) in group {
                if let cutout { found.append((slot, cutout)) }
            }
            return found.sorted { $0.0 < $1.0 }.map(\.1)
        }
        let plateArt = try await plate
        guard !plateArt.placeholder, let plateURL = URL(string: plateArt.url) else { throw URLError(.cannotDecodeContentData) }
        let platePath = try await media.store(from: plateURL, named: "\(book.id)-p\(page.index)-v\(page.version)-plate.png")
        return PageLayers(platePath: platePath, cutouts: cutouts)
    }

    /// The bible's characters named in the page's words (at most `maxCutouts`); if none are
    /// named, one unnamed "main character" cutout.
    static func charactersOnPage(_ page: PageContent, bible: StoryBible) -> [Character?] {
        let text = page.text.lowercased()
        let named = bible.characters.filter { text.contains($0.name.lowercased()) }
        if !named.isEmpty { return Array(named.prefix(maxCutouts)) }
        if let first = bible.characters.first { return [first] }
        return [nil]
    }

    /// Keys the flat green out of a cutout and returns it as a PNG with transparency.
    static func keyedPNG(from path: String) -> Data? {
        guard let image = UIImage(contentsOfFile: path)?.cgImage,
              let keyed = BackgroundKey.removeBackground(from: image)
        else { return nil }
        return UIImage(cgImage: keyed).pngData()
    }
}
