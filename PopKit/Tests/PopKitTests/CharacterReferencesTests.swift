import Foundation
import Testing
@testable import PopKit

@Suite struct CharacterReferencesTests {
    private let maya = Character(id: "maya", name: "Maya", description: "a small blue dragon")
    private let fox = Character(id: "fox", name: "Fox", description: "a friendly orange fox")

    @Test func aNewBibleKeepsTheReferencesAlreadyMade() {
        let old = StoryBible(characters: [maya.with(referencePath: "u/b/character-maya-v1.png"), fox])
        let fresh = StoryBible(title: "T", characters: [maya, fox, Character(id: "owl", name: "Owl", description: "wise")])
        let merged = fresh.carryingReferences(from: old)
        #expect(merged.characters.map(\.referencePath) == ["u/b/character-maya-v1.png", nil, nil])
        #expect(merged.title == "T")
    }

    @Test func aReferenceTheServerSendsBackIsKept() {
        let old = StoryBible(characters: [maya.with(referencePath: "old.png")])
        let fresh = StoryBible(characters: [maya.with(referencePath: "new.png")])
        #expect(fresh.carryingReferences(from: old).characters.first?.referencePath == "new.png")
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
