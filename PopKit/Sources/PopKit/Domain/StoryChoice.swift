import Foundation

/// What kind of question a page asks (IMP-25): either/or tiles, an open "what's the plan?"
/// with tiles as a floor, or a prompt that's only for talking ("Can you roar like Rex?").
public enum QuestionKind: String, Codable, Sendable, Equatable {
    case choice
    case open
    case talkOnly
}

/// One tap-to-steer answer to a page's question: a picture tile the kid can tap, and the one
/// sentence the story engine follows if they do.
public struct StoryChoice: Codable, Equatable, Sendable, Hashable {
    public let label: String
    /// An SF Symbol from the server's allow-list.
    public let symbol: String
    public let direction: String
    /// This choice is the path's own next beat: tapping it changes nothing but the answer.
    public let followsPath: Bool

    public init(label: String, symbol: String, direction: String, followsPath: Bool) {
        self.label = label
        self.symbol = symbol
        self.direction = direction
        self.followsPath = followsPath
    }

    private enum CodingKeys: String, CodingKey { case label, symbol, direction, followsPath }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decode(String.self, forKey: .label)
        symbol = try container.decode(String.self, forKey: .symbol)
        direction = try container.decode(String.self, forKey: .direction)
        followsPath = try container.decodeIfPresent(Bool.self, forKey: .followsPath) ?? false
    }
}
