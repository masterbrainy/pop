import Foundation

/// Keeps each character looking the same on every page (PRD S6). The first time a character
/// is drawn, that page's picture becomes its reference at once, and a 1:1 reference sheet is
/// made from it; the art function then attaches the reference to every later page, cutout and
/// the cover.
public enum CharacterReferences {
    /// Characters that still need a reference sheet and aren't already being made.
    public static func missing(in bible: StoryBible, alreadyRequested: Set<String>) -> [Character] {
        bible.characters.filter { $0.referencePath == nil && !alreadyRequested.contains($0.id) }
    }

    /// Like `missing`, but only the characters a page's art prompt names: a picture can only be
    /// the reference for characters that are in it.
    public static func missing(in bible: StoryBible, onPageWith artPrompt: String, alreadyRequested: Set<String>) -> [Character] {
        named(in: artPrompt, among: missing(in: bible, alreadyRequested: alreadyRequested))
    }

    /// The characters `artPrompt` names by their whole name or id, ignoring case (mirrors the
    /// art function's `charactersIn`).
    public static func named(in artPrompt: String, among characters: [Character]) -> [Character] {
        characters.filter { mentions(artPrompt, $0.name) || mentions(artPrompt, $0.id) }
    }

    /// Asks for `character` alone, drawn to match how it looks in the page picture at `stillPath`.
    public static func request(for character: Character, bookId: UUID, fromStill stillPath: String) -> ArtRequest {
        let prompt = "A character reference sheet: \(character.name) alone, full body, facing the viewer, on a plain soft background. "
            + "Draw \(character.name) exactly as they look in the attached picture: same colours, shape, markings and clothing."
        return ArtRequest(bookId: bookId, kind: .character, version: 1, prompt: prompt,
                          characters: [character.with(referencePath: stillPath)], characterId: character.id)
    }

    private static func mentions(_ text: String, _ phrase: String) -> Bool {
        let words = phrase.split(whereSeparator: \.isWhitespace).map { NSRegularExpression.escapedPattern(for: String($0)) }
        guard !words.isEmpty,
              let regex = try? NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}_])\(words.joined(separator: "\\s+"))(?![\\p{L}\\p{N}_])",
                                                   options: [.caseInsensitive])
        else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}

extension Character {
    public func with(referencePath: String?) -> Character {
        Character(id: id, name: name, description: description, referencePath: referencePath)
    }
}

extension StoryBible {
    /// The server's cap on a bible's characters (schemas.ts `storyBibleSchema`).
    static let maxCharacters = 10

    /// This bible, with every character `old` already knew kept exactly as it was: same id,
    /// name, description and reference. The story engine returns the cast on every call and
    /// can rename, re-describe or drop a character; any of those made later pictures draw a
    /// different one. Matched by id, else by name; characters it dropped stay (up to the cap).
    public func keepingCharacters(from old: StoryBible) -> StoryBible {
        var used: Set<String> = []
        var merged: [Character] = []
        for fresh in characters {
            let match = old.characters.first { known in
                !used.contains(known.id) && (known.id == fresh.id || known.name.caseInsensitiveCompare(fresh.name) == .orderedSame)
            }
            if let match {
                used.insert(match.id)
                merged.append(match.with(referencePath: match.referencePath ?? fresh.referencePath))
            } else if !merged.contains(where: { $0.id == fresh.id }) {
                merged.append(fresh)
            }
        }
        let dropped = old.characters.filter { known in !used.contains(known.id) && !merged.contains { $0.id == known.id } }
        merged += dropped.prefix(max(0, Self.maxCharacters - merged.count))
        return with(characters: merged)
    }

    /// Sets `path` as the reference for character `id` if it has none yet.
    public func settingReference(_ path: String, for id: String) -> StoryBible {
        let updated = characters.map { $0.id == id && $0.referencePath == nil ? $0.with(referencePath: path) : $0 }
        return with(characters: updated)
    }

    /// Swaps the page picture standing in as `id`'s reference for its finished reference sheet;
    /// a reference set some other way is left alone.
    public func replacingReference(_ provisional: String, with sheet: String, for id: String) -> StoryBible {
        let updated = characters.map { c in
            c.id == id && (c.referencePath == nil || c.referencePath == provisional) ? c.with(referencePath: sheet) : c
        }
        return with(characters: updated)
    }
}
