import Foundation

/// How an answer that isn't a picture tile was given: typed, or said into the card's mic.
/// The server moderates both, and spoken words also get the real-harm check (they may be the kid's).
public enum AnswerSource: String, Codable, Sendable, Equatable {
    case typed
    case speech
}

/// One guided-setup card's answer (IMP-24): a picture tile, sent by id only (the server turns
/// it into words), or a few words of the parent's or kid's own.
public enum BriefAnswer: Equatable, Sendable {
    case tile(String)
    case text(String, via: AnswerSource)

    /// The longest own-words answer the server accepts.
    public static let maxTextLength = 80

    /// Own words, trimmed and cut to `maxTextLength`; nil when there's nothing left.
    public static func answer(text raw: String, via source: AnswerSource) -> BriefAnswer? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let capped = String(trimmed.prefix(maxTextLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        return .text(capped, via: source)
    }

    public var tileId: String? {
        if case let .tile(id) = self { id } else { nil }
    }
}

extension BriefAnswer: Codable {
    private enum CodingKeys: String, CodingKey { case tile, text, via }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let tile = try container.decodeIfPresent(String.self, forKey: .tile) {
            self = .tile(tile)
            return
        }
        self = .text(try container.decode(String.self, forKey: .text), via: try container.decode(AnswerSource.self, forKey: .via))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .tile(id):
            try container.encode(id, forKey: .tile)
        case let .text(text, source):
            try container.encode(text, forKey: .text)
            try container.encode(source, forKey: .via)
        }
    }
}

/// "How should it feel?" (the fourth card).
public enum StoryMood: String, Codable, CaseIterable, Sendable {
    case silly
    case cosy
    case brave
}

/// The optional "what's it for" chip. A real moment and teaching open today's text fields.
public enum StoryPurpose: String, Codable, CaseIterable, Sendable {
    case fun
    case bedtime
    case realMoment
    case teach
}

public struct StoryBrief: Codable, Equatable, Sendable {
    public let interests: [String]
    /// A real moment the story helps with (first day of school, a new sibling…), told gently (S11).
    public let realMoment: String?
    /// "Anything you'd like this story to teach?" It only goes into the prompt; there's no lesson subsystem.
    public let teach: String?
    public let language: String
    /// The guided setup's cards (IMP-24); nil when skipped, and in books made before them.
    public let hero: BriefAnswer?
    public let place: BriefAnswer?
    public let problem: BriefAnswer?
    public let mood: StoryMood?
    public let purpose: StoryPurpose?

    public init(
        interests: [String], realMoment: String? = nil, teach: String? = nil, language: String = "en",
        hero: BriefAnswer? = nil, place: BriefAnswer? = nil, problem: BriefAnswer? = nil, mood: StoryMood? = nil, purpose: StoryPurpose? = nil
    ) {
        self.interests = interests
        self.realMoment = realMoment
        self.teach = teach
        self.language = language
        self.hero = hero
        self.place = place
        self.problem = problem
        self.mood = mood
        self.purpose = purpose
    }

    /// Whether this book says what it's about itself (its own interests or a card answer), so the
    /// kid profile's interests stay out of it.
    public var hasOwnSetup: Bool {
        !interests.isEmpty || hero != nil || place != nil || problem != nil
    }

    /// This brief with other interests, keeping every other answer.
    public func with(interests: [String]) -> StoryBrief {
        StoryBrief(interests: interests, realMoment: realMoment, teach: teach, language: language,
                   hero: hero, place: place, problem: problem, mood: mood, purpose: purpose)
    }
}

extension KidProfile {
    /// The profile without the sample kid's placeholder interests ("foxes, stars"), which would
    /// otherwise steer every new book towards foxes. Interests a parent chose are kept.
    public func droppingSampleInterests() -> KidProfile {
        guard interests == SampleBooks.kid.interests else { return self }
        return KidProfile(id: id, firstName: firstName, readingLevel: readingLevel, interests: [])
    }
}
