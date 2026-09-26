import Foundation

/// The guided setup (IMP-24): four cards anyone can answer by tapping or speaking, with
/// "Surprise me" on each. Either/or only, and few options: 2 tiles for Listeners, 3 for older
/// kids (the view adds "something else"), since working memory holds about 2–3 items around
/// age 5 (Cowan 2016). The kid profile's interests only ever become suggested tiles here.
public enum SetupCards {
    /// How many tiles a card shows at this reading level.
    public static func optionCount(for level: ReadingLevel) -> Int {
        level == .listener ? 2 : 3
    }

    public static func tile(id: String) -> SetupTile? {
        tiles.first { $0.id == id }
    }

    /// The tiles a card offers: for the hero the child first, then tiles matching the profile's
    /// (and the book's) interests, then the catalog's own order. Always the same for the same input.
    public static func options(card: SetupCard, level: ReadingLevel, brief: StoryBrief, kid: KidProfile) -> [SetupTile] {
        let eligible = eligibleTiles(card: card, level: level)
        let child = card == .hero ? eligible.filter { $0.id == kidTileId } : []
        let favourites = interestTiles(kid.interests + brief.interests, among: eligible)
        var seen = Set<String>()
        let ordered = (child + favourites + eligible).filter { seen.insert($0.id).inserted }
        return Array(ordered.prefix(optionCount(for: level)))
    }

    /// "Surprise me": any tile this card and level can have.
    public static func surprise<R: RandomNumberGenerator>(card: SetupCard, level: ReadingLevel, rng: inout R) -> SetupTile? {
        eligibleTiles(card: card, level: level).randomElement(using: &rng)
    }

    /// The faces on the mood card: two for Listeners, three for older kids.
    public static func moods(for level: ReadingLevel) -> [StoryMood] {
        level == .listener ? [.silly, .cosy] : StoryMood.allCases
    }

    /// The option `spoken` names (the earliest one named, if several), or nil when it names
    /// none, in which case the words themselves become the answer. Whole words only.
    public static func match(spoken: String, options: [SetupTile], kidName: String? = nil) -> SetupTile? {
        let words = normalizedWords(spoken)
        guard !words.isEmpty else { return nil }
        let named = options.compactMap { option -> (position: Int, tile: SetupTile)? in
            var keywords = option.keywords
            if option.id == kidTileId, let kidName { keywords.append(kidName) }
            let positions = keywords.compactMap { position(of: normalizedWords($0), in: words) }
            return positions.min().map { ($0, option) }
        }
        return named.min { $0.position < $1.position }?.tile
    }

    /// A brief from a scripted setup, e.g. `hero:kid,place:pond,problem:lost,mood:silly`
    /// (`-setup` launch option). An answer that isn't a tile on that card becomes typed words.
    public static func brief(fromScript script: String) -> StoryBrief {
        var answers: [SetupCard: BriefAnswer] = [:]
        var mood: StoryMood?
        var purpose: StoryPurpose?
        for entry in script.split(separator: ",") {
            let parts = entry.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let (key, value) = (parts[0].lowercased(), parts[1])
            if let card = SetupCard(rawValue: key) {
                answers[card] = answer(value, on: card)
            } else if key == "mood" {
                mood = StoryMood(rawValue: value.lowercased())
            } else if key == "purpose" {
                purpose = StoryPurpose(rawValue: value)
            }
        }
        return StoryBrief(interests: [], hero: answers[.hero], place: answers[.place], problem: answers[.problem], mood: mood, purpose: purpose)
    }

    // MARK: - helpers

    private static func eligibleTiles(card: SetupCard, level: ReadingLevel) -> [SetupTile] {
        tiles.filter { $0.card == card && $0.levels.contains(level) }
    }

    /// Tiles whose keywords appear in any of `interests`, in the interests' order.
    private static func interestTiles(_ interests: [String], among eligible: [SetupTile]) -> [SetupTile] {
        interests.flatMap { interest -> [SetupTile] in
            let words = normalizedWords(interest)
            return eligible.filter { tile in tile.keywords.contains { position(of: normalizedWords($0), in: words) != nil } }
        }
    }

    private static func answer(_ value: String, on card: SetupCard) -> BriefAnswer? {
        if let tile = tile(id: value.lowercased()), tile.card == card { return .tile(tile.id) }
        return BriefAnswer.answer(text: value, via: .typed)
    }

    private static func normalizedWords(_ text: String) -> [String] {
        // `Swift.Character`: PopKit has its own `Character` (a story's cast member).
        let spaced = String(text.lowercased().map { (letter: Swift.Character) -> Swift.Character in
            letter.isLetter || letter.isNumber ? letter : " "
        })
        return spaced.split(separator: " ").map(String.init)
    }

    /// Where the word sequence `phrase` first starts in `words`, if it does.
    private static func position(of phrase: [String], in words: [String]) -> Int? {
        guard !phrase.isEmpty, phrase.count <= words.count else { return nil }
        return (0...(words.count - phrase.count)).first { Array(words[$0..<($0 + phrase.count)]) == phrase }
    }
}
