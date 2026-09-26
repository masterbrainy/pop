import Foundation
import Testing
@testable import PopKit

/// Covers `HeroCharacter`: the kid's drawing becomes an `art` request, and once its
/// reference sheet is ready, it seeds the book's bible and brief (ROADMAP Phase 8.2).
struct HeroCharacterTests {
    private func book() -> Book {
        Book(kidId: UUID(), brief: StoryBrief(interests: ["dinosaurs"]), createdAt: .now)
    }

    @Test func requestBuildsADrawingKindArtRequestWithTheHeroCharacterId() {
        let drawing = HeroDrawing(imageData: Data([0xAA, 0xBB]), description: "a purple cat with wings")
        let bookId = UUID()
        let request = HeroCharacter.request(for: drawing, bookId: bookId)
        #expect(request.bookId == bookId)
        #expect(request.kind == .drawing)
        #expect(request.characterId == HeroCharacter.id)
        #expect(request.prompt == drawing.description)
        #expect(request.drawing == drawing.base64)
    }

    @Test func namingTitleCasesTheDescriptionAndDropsLeadingArticles() {
        #expect(HeroCharacter.name(from: "a purple cat with wings") == "Purple Cat With Wings")
        #expect(HeroCharacter.name(from: "THE brave dragon") == "Brave Dragon")
        #expect(HeroCharacter.name(from: "  ") == "Hero")
        #expect(HeroCharacter.name(from: "a") == "Hero")
    }

    @Test func seedingAddsTheHeroToTheBibleWithItsReferencePath() {
        let drawing = HeroDrawing(imageData: Data(), description: "a purple cat with wings")
        let seeded = HeroCharacter.seeding(book(), drawing: drawing, referencePath: "u/b/hero.png")
        let hero = seeded.bible.characters.first { $0.id == HeroCharacter.id }
        #expect(hero?.name == "Purple Cat With Wings")
        #expect(hero?.referencePath == "u/b/hero.png")
        #expect(hero?.description == drawing.description)
    }

    @Test func seedingMentionsTheHeroInTheBriefsInterests() {
        let drawing = HeroDrawing(imageData: Data(), description: "a purple cat with wings")
        let seeded = HeroCharacter.seeding(book(), drawing: drawing, referencePath: "u/b/hero.png")
        #expect(seeded.brief.interests.contains("a purple cat with wings"))
        #expect(seeded.brief.interests.contains("dinosaurs"))
    }

    @Test func seedingDoesNotDuplicateAnInterestAlreadyThere() {
        let drawing = HeroDrawing(imageData: Data(), description: "dinosaurs")
        let seeded = HeroCharacter.seeding(book(), drawing: drawing, referencePath: "u/b/hero.png")
        #expect(seeded.brief.interests == ["dinosaurs"])
    }

    @Test func seedingReplacesAnyExistingHeroRatherThanDuplicatingIt() {
        let existing = Character(id: HeroCharacter.id, name: "Old Hero", description: "an old one")
        let bookWithHero = book().with(bible: StoryBible(characters: [existing]))
        let drawing = HeroDrawing(imageData: Data(), description: "a purple cat with wings")
        let seeded = HeroCharacter.seeding(bookWithHero, drawing: drawing, referencePath: "u/b/hero.png")
        #expect(seeded.bible.characters.count == 1)
        #expect(seeded.bible.characters[0].name == "Purple Cat With Wings")
    }
}
