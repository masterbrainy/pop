import Foundation

/// Turns a kid's own drawing into the story's hero (ROADMAP Phase 8.2): the drawing becomes
/// a character reference sheet via the `art` function's `drawing` kind (docs/CONTRACTS.md §3),
/// and the result seeds the story bible as a character named from what the kid said it is, so
/// the story engine draws it — and only it — as this book's hero from the first page on.
public enum HeroCharacter {
    public static let id = "hero"

    /// The `art` request that turns `drawing` into a reference sheet, made once when the
    /// book starts (before the first turn).
    public static func request(for drawing: HeroDrawing, bookId: UUID) -> ArtRequest {
        ArtRequest(bookId: bookId, kind: .drawing, version: 1, prompt: drawing.description, characterId: id, drawing: drawing.base64)
    }

    /// `book`, with the hero added to the bible's characters (so every later page and
    /// picture draws it consistently) and mentioned in the brief's interests (so the
    /// story engine leans toward it as the protagonist from the very first page).
    public static func seeding(_ book: Book, drawing: HeroDrawing, referencePath: String) -> Book {
        let character = Character(id: id, name: name(from: drawing.description), description: drawing.description, referencePath: referencePath)
        return book.with(bible: book.bible.addingHero(character)).with(brief: book.brief.addingInterest(drawing.description))
    }

    /// A short title-cased name from the kid's description ("a purple cat with wings" →
    /// "Purple Cat With Wings"), dropping leading articles and falling back to "Hero"
    /// if there's nothing usable.
    static func name(from description: String) -> String {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Hero" }
        let skippable: Set<String> = ["a", "an", "the"]
        let words = trimmed.split(separator: " ").filter { !skippable.contains($0.lowercased()) }
        guard !words.isEmpty else { return "Hero" }
        return words.prefix(4).map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined(separator: " ")
    }
}

extension StoryBible {
    /// This bible with `hero` added or replacing any existing character with the same id.
    func addingHero(_ hero: Character) -> StoryBible {
        let others = characters.filter { $0.id != hero.id }
        return StoryBible(title: title, setting: setting, characters: others + [hero], directions: directions)
    }
}

extension StoryBrief {
    /// This brief with `interest` appended, unless something close to it is already there.
    func addingInterest(_ interest: String) -> StoryBrief {
        let trimmed = interest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !interests.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return self }
        return StoryBrief(interests: interests + [trimmed], realMoment: realMoment, teach: teach, language: language)
    }
}
