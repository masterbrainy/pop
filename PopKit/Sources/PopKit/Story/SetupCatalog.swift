import Foundation

/// A guided-setup card that's answered with picture tiles (IMP-24). The fourth card, the
/// mood, is answered with faces (`StoryMood`).
public enum SetupCard: String, CaseIterable, Sendable {
    case hero
    case place
    case problem

    /// The card's question, said aloud when the child is there.
    public var prompt: String {
        switch self {
        case .hero: "Who's the hero?"
        case .place: "Where does it happen?"
        case .problem: "What goes wrong?"
        }
    }
}

/// One picture tile. Only its id travels; the server's `setup_tiles.json` turns it into words.
public struct SetupTile: Equatable, Sendable, Identifiable, Hashable {
    public let id: String
    public let card: SetupCard
    public let label: String
    public let symbol: String
    public let levels: Set<ReadingLevel>
    /// Words that name this tile, for matching speech and profile interests.
    public let keywords: [String]

    /// The tile's caption; the child's own tile shows their name.
    public func label(kidName: String) -> String {
        id == SetupCards.kidTileId ? kidName : label
    }
}

extension SetupCards {
    static let kidTileId = "kid"
    private static let all: Set<ReadingLevel> = [.listener, .earlyReader, .reader]
    private static let older: Set<ReadingLevel> = [.earlyReader, .reader]

    private static func tile(_ id: String, _ card: SetupCard, _ label: String, _ symbol: String, _ levels: Set<ReadingLevel>, _ keywords: [String]) -> SetupTile {
        SetupTile(id: id, card: card, label: label, symbol: symbol, levels: levels, keywords: [id] + keywords)
    }

    /// Mirrors `supabase/functions/_shared/setup_tiles.json`, in the same order
    /// (`SetupCardsCatalogTests` checks ids, cards, symbols and levels).
    public static let tiles: [SetupTile] = [
        tile("kid", .hero, "Me", "figure.child", all, ["me", "myself"]),
        tile("dragon", .hero, "Dragon", "lizard.fill", all, ["dragons", "dinosaur", "dinosaurs", "dino", "dinos"]),
        tile("bunny", .hero, "Bunny", "hare.fill", all, ["bunnies", "rabbit", "rabbits", "hare"]),
        tile("cat", .hero, "Cat", "cat.fill", all, ["cats", "kitten", "kittens", "kitty"]),
        tile("dog", .hero, "Puppy", "dog.fill", all, ["dogs", "puppy", "puppies", "pup"]),
        tile("bird", .hero, "Bird", "bird.fill", all, ["birds", "owl", "owls", "duck", "ducks"]),
        tile("fish", .hero, "Fish", "fish.fill", all, ["fishes", "goldfish"]),
        tile("turtle", .hero, "Turtle", "tortoise.fill", all, ["turtles", "tortoise"]),
        tile("bear", .hero, "Teddy", "teddybear.fill", all, ["bears", "teddy", "teddies", "teddy bear"]),
        tile("fox", .hero, "Fox", "pawprint.fill", all, ["foxes"]),
        tile("ladybug", .hero, "Ladybug", "ladybug.fill", all, ["ladybugs", "ladybird", "ladybirds", "bug", "bugs", "beetle", "insects"]),
        tile("unicorn", .hero, "Unicorn", "sparkles", older, ["unicorns", "pony", "ponies", "horse", "horses"]),
        tile("knight", .hero, "Knight", "shield.fill", older, ["knights", "princess", "prince", "king", "queen"]),
        tile("robot", .hero, "Robot", "gearshape.fill", older, ["robots", "machine", "machines"]),

        tile("forest", .place, "Forest", "tree.fill", all, ["woods", "wood", "trees"]),
        tile("beach", .place, "Beach", "beach.umbrella.fill", all, ["seaside", "sand", "shells"]),
        tile("space", .place, "Space", "moon.stars.fill", all, ["stars", "moon", "planet", "planets", "rocket", "rockets"]),
        tile("pond", .place, "Pond", "drop.fill", all, ["lake", "frog", "frogs"]),
        tile("castle", .place, "Castle", "building.columns.fill", all, ["castles", "palace"]),
        tile("garden", .place, "Garden", "leaf.fill", all, ["flowers", "flower"]),
        tile("home", .place, "Home", "house.fill", all, ["house", "bedroom"]),
        tile("farm", .place, "Farm", "carrot.fill", all, ["farms", "tractor", "tractors", "cow", "cows"]),
        tile("snow", .place, "Snow", "snowflake", all, ["snowy", "ice", "winter", "snowman"]),
        tile("sky", .place, "Sky", "cloud.fill", all, ["clouds", "cloud", "balloon", "balloons"]),
        tile("ocean", .place, "Ocean", "water.waves", older, ["underwater", "sea", "mermaid", "mermaids", "whale", "whales"]),
        tile("mountain", .place, "Mountain", "mountain.2.fill", older, ["mountains", "hill", "hills"]),
        tile("jungle", .place, "Jungle", "leaf.circle.fill", older, ["monkey", "monkeys", "lion", "lions", "tiger", "tigers"]),
        tile("city", .place, "City", "building.2.fill", older, ["town", "car", "cars", "train", "trains", "bus"]),

        tile("lost", .problem, "Lost", "questionmark.circle.fill", all, ["lose", "missing", "find"]),
        tile("rain", .problem, "Rain", "cloud.rain.fill", all, ["rainy", "storm", "puddle", "puddles"]),
        tile("sleepy", .problem, "Can't sleep", "moon.zzz.fill", all, ["sleep", "asleep", "bedtime", "tired"]),
        tile("hungry", .problem, "Hungry", "fork.knife", all, ["snack", "food", "lunch"]),
        tile("wind", .problem, "Windy", "wind", all, ["windy", "hat", "blown"]),
        tile("share", .problem, "Sharing", "hand.raised.fill", all, ["sharing", "toy", "toys"]),
        tile("stuck", .problem, "Stuck", "arrow.up.circle.fill", older, ["climb", "stuck up"]),
        tile("shy", .problem, "Shy", "person.2.fill", older, ["new friend", "friend", "friends"]),
        tile("broken", .problem, "Broken", "wrench.and.screwdriver.fill", older, ["breaks", "broke", "fix"]),
        tile("party", .problem, "Party", "gift.fill", older, ["birthday", "cake"]),
        tile("noise", .problem, "A noise", "speaker.wave.3.fill", older, ["noisy", "sound", "bang"]),
        tile("race", .problem, "A race", "flag.checkered", [.reader], ["racing", "running", "run"]),
    ]
}
