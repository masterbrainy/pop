import Foundation

/// Keeps each character looking the same on every page (PRD S6). The first time a character
/// is drawn, a 1:1 reference sheet is made from that page's picture; the art function then
/// attaches it to every later page, cutout and the cover.
public enum CharacterReferences {
    /// Characters that still need a reference sheet and aren't already being made.
    public static func missing(in bible: StoryBible, alreadyRequested: Set<String>) -> [Character] {
        bible.characters.filter { $0.referencePath == nil && !alreadyRequested.contains($0.id) }
    }

    /// Asks for `character` alone, drawn to match how it looks in the page picture at `stillPath`.
    public static func request(for character: Character, bookId: UUID, fromStill stillPath: String) -> ArtRequest {
        let prompt = "A character reference sheet: \(character.name) alone, full body, facing the viewer, on a plain soft background. "
            + "Draw \(character.name) exactly as they look in the attached picture: same colours, shape, markings and clothing."
        return ArtRequest(bookId: bookId, kind: .character, version: 1, prompt: prompt,
                          characters: [character.with(referencePath: stillPath)], characterId: character.id)
    }
}

extension Character {
    public func with(referencePath: String?) -> Character {
        Character(id: id, name: name, description: description, referencePath: referencePath)
    }
}

extension StoryBible {
    /// This bible, keeping any reference sheet `old` already had for a character that this
    /// one leaves without (the story engine returns characters without their references).
    public func carryingReferences(from old: StoryBible) -> StoryBible {
        let known = Dictionary(old.characters.compactMap { c in c.referencePath.map { (c.id, $0) } }) { first, _ in first }
        let merged = characters.map { $0.referencePath == nil ? $0.with(referencePath: known[$0.id]) : $0 }
        return StoryBible(title: title, setting: setting, characters: merged, directions: directions)
    }

    /// Sets `path` as the reference for character `id` if it has none yet.
    public func settingReference(_ path: String, for id: String) -> StoryBible {
        let updated = characters.map { $0.id == id && $0.referencePath == nil ? $0.with(referencePath: path) : $0 }
        return StoryBible(title: title, setting: setting, characters: updated, directions: directions)
    }
}
