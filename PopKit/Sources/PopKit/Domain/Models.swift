import Foundation

// The domain model shared by the app and the server (docs/CONTRACTS.md §1).
// camelCase on the wire; dates are ISO-8601.

public struct KidProfile: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let firstName: String
    public let readingLevel: ReadingLevel
    public let interests: [String]

    public init(id: UUID = UUID(), firstName: String, readingLevel: ReadingLevel, interests: [String]) {
        self.id = id
        self.firstName = firstName
        self.readingLevel = readingLevel
        self.interests = interests
    }
}

public struct ParentSettings: Codable, Equatable, Sendable {
    public let avoidTopics: [String]
    public let readingLevel: ReadingLevel?
    public let language: String

    public init(avoidTopics: [String] = [], readingLevel: ReadingLevel? = nil, language: String = "en") {
        self.avoidTopics = avoidTopics
        self.readingLevel = readingLevel
        self.language = language
    }
}

public struct Character: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    /// The fixed look, reused in every picture (S6).
    public let description: String
    public let referencePath: String?

    public init(id: String, name: String, description: String, referencePath: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.referencePath = referencePath
    }
}

public struct StoryBible: Codable, Equatable, Sendable {
    public let title: String?
    public let setting: String
    public let characters: [Character]
    /// Every direction so far; each one carries into the pages that follow (S7).
    public let directions: [String]
    /// The planned story, one short beat per page, always ending (P-04); empty in books saved before it.
    public let path: [String]

    public init(title: String? = nil, setting: String = "", characters: [Character] = [], directions: [String] = [], path: [String] = []) {
        self.title = title
        self.setting = setting
        self.characters = characters
        self.directions = directions
        self.path = path
    }

    public static let empty = StoryBible()

    private enum CodingKeys: String, CodingKey { case title, setting, characters, directions, path }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        setting = try container.decodeIfPresent(String.self, forKey: .setting) ?? ""
        characters = try container.decodeIfPresent([Character].self, forKey: .characters) ?? []
        directions = try container.decodeIfPresent([String].self, forKey: .directions) ?? []
        path = try container.decodeIfPresent([String].self, forKey: .path) ?? []
    }

    /// The same bible with a different cast, keeping everything else.
    public func with(characters: [Character]) -> StoryBible {
        StoryBible(title: title, setting: setting, characters: characters, directions: directions, path: path)
    }

    /// Whether `pageIndex` is the path's last beat: the ending, with no page behind it.
    public func isEnding(pageIndex: Int) -> Bool {
        !path.isEmpty && pageIndex >= path.count - 1
    }

    /// Whether the path has a page after `pageIndex` to build behind it.
    public func hasPage(after pageIndex: Int) -> Bool {
        pageIndex + 1 < path.count
    }
}

/// The page's animation prompt parts from the `motion-prompt` function; `MotionPromptBuilder` assembles them.
public struct MotionParts: Codable, Equatable, Sendable {
    public let scene: String
    public let motion: String

    public init(scene: String, motion: String) {
        self.scene = scene
        self.motion = motion
    }
}

public struct Cutout: Codable, Equatable, Sendable {
    public let characterId: String
    public let path: String

    public init(characterId: String, path: String) {
        self.characterId = characterId
        self.path = path
    }
}

/// Pop-up layers: the scene without its characters, plus one keyed cutout per character.
public struct PageLayers: Codable, Equatable, Sendable {
    public let platePath: String
    public let cutouts: [Cutout]

    public init(platePath: String, cutouts: [Cutout]) {
        self.platePath = platePath
        self.cutouts = cutouts
    }
}

public struct PageContent: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let index: Int
    /// Bumps on every revision, so late results for an older version can be dropped.
    public let version: Int
    public let text: String
    public let artPrompt: String?
    public let stillPath: String?
    public let layers: PageLayers?
    public let motion: MotionParts?
    public let clipPath: String?
    /// One question for the parent to ask about this page (PRD C3); nil in books saved before it.
    public let question: String?
    /// What kind of question it is (IMP-25); nil when there's no question, or before IMP-25.
    public let questionKind: QuestionKind?
    /// Tap-to-steer answers to the question (IMP-25); nil when it has none.
    public let choices: [StoryChoice]?

    public init(
        id: UUID = UUID(), index: Int, version: Int = 1, text: String, artPrompt: String? = nil,
        stillPath: String? = nil, layers: PageLayers? = nil, motion: MotionParts? = nil, clipPath: String? = nil,
        question: String? = nil, questionKind: QuestionKind? = nil, choices: [StoryChoice]? = nil
    ) {
        self.id = id
        self.index = index
        self.version = version
        self.text = text
        self.artPrompt = artPrompt
        self.stillPath = stillPath
        self.layers = layers
        self.motion = motion
        self.clipPath = clipPath
        self.question = question
        self.questionKind = questionKind
        self.choices = choices
    }

    /// A new version of this page: new words and art prompt, and no media yet (it's regenerated).
    /// Its question and choices were about the old words, so they go too.
    public func revised(text: String, artPrompt: String?) -> PageContent {
        PageContent(id: id, index: index, version: version + 1, text: text, artPrompt: artPrompt)
    }

    public func with(stillPath: String?) -> PageContent {
        copy(stillPath: stillPath)
    }

    public func with(layers: PageLayers?) -> PageContent {
        copy(layers: layers)
    }

    public func with(motion: MotionParts?) -> PageContent {
        copy(motion: motion)
    }

    public func with(clipPath: String?) -> PageContent {
        copy(clipPath: clipPath)
    }

    public func with(text: String) -> PageContent {
        copy(text: text)
    }

    /// This page with a question, keeping its kind and choices; a blank question clears all three.
    public func with(question: String?) -> PageContent {
        with(question: question, kind: questionKind, choices: choices)
    }

    /// This page with a question, its kind and its choices. A blank question has no kind or
    /// choices, and an empty list of choices is stored as none.
    public func with(question: String?, kind: QuestionKind?, choices: [StoryChoice]?) -> PageContent {
        let trimmed = question?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let ask = trimmed, !ask.isEmpty else {
            return copy(question: .some(nil), questionKind: .some(nil), choices: .some(nil))
        }
        let kept = choices?.isEmpty == false ? choices : nil
        return copy(question: .some(ask), questionKind: .some(kind), choices: .some(kept))
    }

    /// This page with some fields changed; everything else (id, version, question, choices) is kept.
    private func copy(
        text: String? = nil, stillPath: String?? = nil, layers: PageLayers?? = nil, motion: MotionParts?? = nil,
        clipPath: String?? = nil, question: String?? = nil, questionKind: QuestionKind?? = nil, choices: [StoryChoice]?? = nil
    ) -> PageContent {
        PageContent(
            id: id, index: index, version: version, text: text ?? self.text, artPrompt: artPrompt,
            stillPath: stillPath ?? self.stillPath, layers: layers ?? self.layers, motion: motion ?? self.motion,
            clipPath: clipPath ?? self.clipPath, question: question ?? self.question,
            questionKind: questionKind ?? self.questionKind, choices: choices ?? self.choices
        )
    }

    /// This page at another index and version (placing, re-numbering), keeping everything else.
    public func renumbered(index: Int, version: Int) -> PageContent {
        PageContent(id: id, index: index, version: version, text: text, artPrompt: artPrompt, stillPath: stillPath, layers: layers,
                    motion: motion, clipPath: clipPath, question: question, questionKind: questionKind, choices: choices)
    }
}

public enum BookStatus: String, Codable, Sendable {
    case draft
    case finished
}

public struct Book: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kidId: UUID
    public let brief: StoryBrief
    public let bible: StoryBible
    public let pages: [PageContent]
    public let status: BookStatus
    public let title: String?
    public let coverPath: String?
    public let createdAt: Date
    public let finishedAt: Date?

    public init(
        id: UUID = UUID(), kidId: UUID, brief: StoryBrief, bible: StoryBible = .empty, pages: [PageContent] = [],
        status: BookStatus = .draft, title: String? = nil, coverPath: String? = nil, createdAt: Date, finishedAt: Date? = nil
    ) {
        self.id = id
        self.kidId = kidId
        self.brief = brief
        self.bible = bible
        self.pages = pages
        self.status = status
        self.title = title
        self.coverPath = coverPath
        self.createdAt = createdAt
        self.finishedAt = finishedAt
    }

    /// "Rex Learns to Share, a story for Maya" (PRD H3).
    public static func coverLine(title: String, firstName: String) -> String {
        "\(title), a story for \(firstName)"
    }

    public func with(pages: [PageContent]) -> Book {
        Book(id: id, kidId: kidId, brief: brief, bible: bible, pages: pages, status: status, title: title, coverPath: coverPath, createdAt: createdAt, finishedAt: finishedAt)
    }

    public func with(bible: StoryBible) -> Book {
        Book(id: id, kidId: kidId, brief: brief, bible: bible, pages: pages, status: status, title: title, coverPath: coverPath, createdAt: createdAt, finishedAt: finishedAt)
    }

    public func with(brief: StoryBrief) -> Book {
        Book(id: id, kidId: kidId, brief: brief, bible: bible, pages: pages, status: status, title: title, coverPath: coverPath, createdAt: createdAt, finishedAt: finishedAt)
    }

    public func finished(title: String, coverPath: String?, at date: Date) -> Book {
        Book(id: id, kidId: kidId, brief: brief, bible: bible, pages: pages, status: .finished, title: title, coverPath: coverPath, createdAt: createdAt, finishedAt: date)
    }
}
