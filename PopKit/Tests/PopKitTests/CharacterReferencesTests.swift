import Foundation
import Testing
@testable import PopKit

@Suite struct CharacterReferencesTests {
    private let sara = Character(id: "sara", name: "Sara", description: "a small blue dragon")
    private let fox = Character(id: "fox", name: "Fox", description: "a friendly orange fox")

    @Test func aNewBibleKeepsTheReferencesAlreadyMade() {
        let old = StoryBible(characters: [sara.with(referencePath: "u/b/character-sara-v1.png"), fox])
        let fresh = StoryBible(title: "T", characters: [sara, fox, Character(id: "owl", name: "Owl", description: "wise")])
        let merged = fresh.keepingCharacters(from: old)
        #expect(merged.characters.map(\.referencePath) == ["u/b/character-sara-v1.png", nil, nil])
        #expect(merged.title == "T")
    }

    @Test func theAppsCurrentReferenceWinsOverTheServersEcho() {
        // The server echoes the reference the app sent; a sheet may have replaced it since.
        let old = StoryBible(characters: [sara.with(referencePath: "sheet.png")])
        let fresh = StoryBible(characters: [sara.with(referencePath: "page-still.png")])
        #expect(fresh.keepingCharacters(from: old).characters.first?.referencePath == "sheet.png")
    }

    @Test func aServerReferenceFillsAnEmptySlot() {
        let old = StoryBible(characters: [sara])
        let fresh = StoryBible(characters: [sara.with(referencePath: "new.png")])
        #expect(fresh.keepingCharacters(from: old).characters.first?.referencePath == "new.png")
    }

    @Test func aKnownCharacterKeepsItsLookWhenTheEngineRedescribesIt() {
        let old = StoryBible(characters: [sara.with(referencePath: "m.png")])
        let fresh = StoryBible(characters: [Character(id: "sara", name: "Sara", description: "a big red dragon")])
        #expect(fresh.keepingCharacters(from: old).characters == [sara.with(referencePath: "m.png")])
    }

    @Test func aKnownCharacterIsMatchedByNameWhenItsIdChanges() {
        let old = StoryBible(characters: [sara.with(referencePath: "m.png")])
        let fresh = StoryBible(characters: [Character(id: "sara_dragon", name: "sara", description: "a dragon")])
        #expect(fresh.keepingCharacters(from: old).characters == [sara.with(referencePath: "m.png")])
    }

    @Test func aCharacterTheEngineLeftOutStays() {
        let old = StoryBible(characters: [sara.with(referencePath: "m.png"), fox])
        let fresh = StoryBible(characters: [fox])
        #expect(fresh.keepingCharacters(from: old).characters.map(\.id) == ["fox", "sara"])
    }

    @Test func leftOutCharactersNeverPassTheCap() {
        let crowd = (0..<10).map { Character(id: "c\($0)", name: "C\($0)", description: "d") }
        let merged = StoryBible(characters: crowd).keepingCharacters(from: StoryBible(characters: [sara]))
        #expect(merged.characters.count == 10)
        #expect(!merged.characters.contains { $0.id == "sara" })
    }

    @Test func onlyCharactersNamedInThePictureGetItAsTheirReference() {
        let bible = StoryBible(characters: [sara, fox])
        let named = CharacterReferences.missing(in: bible, onPageWith: "sara flies over the pond at dusk", alreadyRequested: [])
        #expect(named.map(\.id) == ["sara"])
        #expect(CharacterReferences.missing(in: bible, onPageWith: "Sarapple fields", alreadyRequested: []).isEmpty)
        #expect(CharacterReferences.missing(in: bible, onPageWith: "Sara and Fox", alreadyRequested: ["fox"]).map(\.id) == ["sara"])
    }

    @Test func theFinishedSheetReplacesOnlyTheStandInPicture() {
        let bible = StoryBible(characters: [sara.with(referencePath: "page-0.png"), fox.with(referencePath: "drawing.png")])
        let updated = bible
            .replacingReference("page-0.png", with: "sheet-sara.png", for: "sara")
            .replacingReference("page-0.png", with: "sheet-fox.png", for: "fox")
        #expect(updated.characters.map(\.referencePath) == ["sheet-sara.png", "drawing.png"])
    }

    @Test func missingListsOnlyCharactersWithoutAReference() {
        let bible = StoryBible(characters: [sara.with(referencePath: "m.png"), fox])
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
        let bible = StoryBible(characters: [sara.with(referencePath: "keep.png"), fox])
        let updated = bible.settingReference("fox.png", for: "fox").settingReference("other.png", for: "sara")
        #expect(updated.characters.map(\.referencePath) == ["keep.png", "fox.png"])
    }
}
