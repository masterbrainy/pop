import Foundation
import Testing
@testable import PopKit

/// The app sends tile ids and the server turns them into phrases from
/// `supabase/functions/_shared/setup_tiles.json`: both sides must list the same tiles.
struct SetupCardsCatalogTests {
    private struct Catalog: Decodable {
        struct Tile: Decodable {
            let id: String
            let card: String
            let phrase: String
            let symbol: String
            let levels: [String]
        }
        let tiles: [Tile]
    }

    private func serverCatalog() throws -> Catalog {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // PopKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // PopKit
            .deletingLastPathComponent() // repo root
        let url = repo.appending(path: "supabase/functions/_shared/setup_tiles.json")
        return try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
    }

    @Test func theAppAndServerListTheSameTilesInTheSameOrder() throws {
        let server = try serverCatalog().tiles
        #expect(SetupCards.tiles.map(\.id) == server.map(\.id))
    }

    @Test func eachTileHasTheSameCardSymbolAndLevelsOnBothSides() throws {
        let server = try serverCatalog().tiles
        for (app, remote) in zip(SetupCards.tiles, server) {
            #expect(app.card.rawValue == remote.card, "\(app.id) card")
            #expect(app.symbol == remote.symbol, "\(app.id) symbol")
            #expect(Set(app.levels.map(\.rawValue)) == Set(remote.levels), "\(app.id) levels")
            #expect(!remote.phrase.isEmpty)
        }
    }

    @Test func tileIdsAreUnique() {
        #expect(Set(SetupCards.tiles.map(\.id)).count == SetupCards.tiles.count)
    }

    @Test func everyCardHasEnoughTilesForEveryLevel() {
        for level in ReadingLevel.allCases {
            for card in SetupCard.allCases {
                #expect(SetupCards.tiles.filter { $0.card == card && $0.levels.contains(level) }.count >= 3)
            }
        }
    }
}
