import Foundation
import Testing
@testable import PopKit

@Suite struct CharacterReferencesTests {
    private let maya = Character(id: "maya", name: "Maya", description: "a small blue dragon")
    private let fox = Character(id: "fox", name: "Fox", description: "a friendly orange fox")

    @Test func aNewBibleKeepsTheReferencesAlreadyMade() {
        let old = StoryBible(characters: [maya.with(referencePath: "u/b/character-maya-v1.png"), fox])
        let fresh = StoryBible(title: "T", characters: [maya, fox, Character(id: "owl", name: "Owl", description: "wise")])
        let merged = fresh.keepingCharacters(from: old)
        #expect(merged.characters.map(\.referencePath) == ["u/b/character-maya-v1.png", nil, nil])
        #expect(merged.title == "T")
    }

    @Test func theAppsCurrentReferenceWinsOverTheServersEcho() {
        // The server echoes the reference the app sent; a sheet may have replaced it since.
        let old = StoryBible(characters: [maya.with(referencePath: "sheet.png")])
        let fresh = StoryBible(characters: [maya.with(referencePath: "page-still.png")])
        #expect(fresh.keepingCharacters(from: old).characters.first?.referencePath == "sheet.png")
    }

    @Test func aServerReferenceFillsAnEmptySlot() {
        let old = StoryBible(characters: [maya])
        let fresh = StoryBible(characters: [maya.with(referencePath: "new.png")])
        #expect(fresh.keepingCharacters(from: old).characters.first?.referencePath == "new.png")
    }

    @Test func aKnownCharacterKeepsItsLookWhenTheEngineRedescribesIt() {
        let old = StoryBible(characters: [maya.with(referencePath: "m.png")])
        let fresh = StoryBible(characters: [Character(id: "maya", name: "Maya", description: "a big red dragon")])
        #expect(fresh.keepingCharacters(from: old).characters == [maya.with(referencePath: "m.png")])
    }

    @Test func aKnownCharacterIsMatchedByNameWhenItsIdChanges() {
        let old = StoryBible(characters: [maya.with(referencePath: "m.png")])
        let fresh = StoryBible(characters: [Character(id: "maya_dragon", name: "maya", description: "a dragon")])
        #expect(fresh.keepingCharacters(from: old).characters == [maya.with(referencePath: "m.png")])
    }

    @Test func aCharacterTheEngineLeftOutStays() {
        let old = StoryBible(characters: [maya.with(referencePath: "m.png"), fox])
        let fresh = StoryBible(characters: [fox])
        #expect(fresh.keepingCharacters(from: old).characters.map(\.id) == ["fox", "maya"])
    }

    @Test func leftOutCharactersNeverPassTheCap() {
        let crowd = (0..<10).map { Character(id: "c\($0)", name: "C\($0)", description: "d") }
        let merged = StoryBible(characters: crowd).keepingCharacters(from: StoryBible(characters: [maya]))
        #expect(merged.characters.count == 10)
        #expect(!merged.characters.contains { $0.id == "maya" })
    }

    @Test func onlyCharactersNamedInThePictureGetItAsTheirReference() {
        let bible = StoryBible(characters: [maya, fox])
        let named = CharacterReferences.missing(in: bible, onPageWith: "maya flies over the pond at dusk", alreadyRequested: [])
        #expect(named.map(\.id) == ["maya"])
        #expect(CharacterReferences.missing(in: bible, onPageWith: "Mayapple fields", alreadyRequested: []).isEmpty)
        #expect(CharacterReferences.missing(in: bible, onPageWith: "Maya and Fox", alreadyRequested: ["fox"]).map(\.id) == ["maya"])
    }

    @Test func theFinishedSheetReplacesOnlyTheStandInPicture() {
        let bible = StoryBible(characters: [maya.with(referencePath: "page-0.png"), fox.with(referencePath: "drawing.png")])
        let updated = bible
            .replacingReference("page-0.png", with: "sheet-maya.png", for: "maya")
            .replacingReference("page-0.png", with: "sheet-fox.png", for: "fox")
        #expect(updated.characters.map(\.referencePath) == ["sheet-maya.png", "drawing.png"])
    }

    @Test func missingListsOnlyCharactersWithoutAReference() {
        let bible = StoryBible(characters: [maya.with(referencePath: "m.png"), fox])
        #expect(CharacterReferences.missing(in: bible, alreadyRequested: []).map(\.id) == ["fox"])
        #expect(CharacterReferences.missing(in: bible, alreadyRequested: ["fox"]).isEmpty)
    }

    @Test func theRequestDrawsTheCharacterFromThePagePicture() {
        let bookId = UUID()
        let request = CharacterReferences.request(for: fox, bookId: bookId, fromStill: "u/b/page-0-v1.png")
        #expect(request.kind == .character)
        #expect(request.characterId == "fox")
        #expect(request.version == 1)
        #expect(request.bookId == bookId)
        #expect(request.characters == [fox.with(referencePath: "u/b/page-0-v1.png")])
        #expect(request.prompt.contains("Fox"))
    }

    @Test func applyingAReferenceOnlyFillsAnEmptySlot() {
        let bible = StoryBible(characters: [maya.with(referencePath: "keep.png"), fox])
        let updated = bible.settingReference("fox.png", for: "fox").settingReference("other.png", for: "maya")
        #expect(updated.characters.map(\.referencePath) == ["keep.png", "fox.png"])
    }
}
