import Foundation
import PopKit

/// Remembers how each character looks, by name, across every story on this device, so a
/// character who comes back in a new book (the child, a pet, a favourite toy) is described,
/// and so drawn, the same way. The first description a name gets is the one that sticks.
enum CharacterLooks {
    private static let key = "characterLooks"

    private static var looks: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// `characters` with each remembered look applied, remembering the looks of new ones.
    static func applying(to characters: [Character]) -> [Character] {
        var saved = looks
        let updated = characters.map { character -> Character in
            let name = Self.name(character.name)
            guard !name.isEmpty else { return character }
            if let look = saved[name] {
                return look == character.description ? character
                    : Character(id: character.id, name: character.name, description: look, referencePath: character.referencePath)
            }
            if !character.description.isEmpty { saved[name] = character.description }
            return character
        }
        if saved != looks { looks = saved }
        return updated
    }

    private static func name(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
