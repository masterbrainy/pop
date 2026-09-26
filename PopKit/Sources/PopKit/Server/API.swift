import Foundation

// Wire request/response types for every Edge Function in docs/CONTRACTS.md §3.
// Field names are camelCase to match the wire exactly. Where a domain type from
// Domain/Models.swift already matches the contract field-for-field, it's reused
// directly (StoryBrief, ParentSettings, StoryBible, Character, MotionParts);
// everything else gets its own small wire type plus an adapter from the domain
// model where one makes sense.

/// An empty JSON object, for requests and responses that carry no fields (`{}`).
public struct EmptyPayload: Codable, Equatable, Sendable {
    public init() {}
}

// MARK: - story-turn

public enum StoryTurnMode: String, Codable, Sendable, Equatable {
    case title
    /// Plan (or re-plan from `index`, following `input`) the story path, and write page `index` (P-04).
    case path
    /// Write page `index` along the existing path.
    case page
}

public enum InputKind: String, Codable, Sendable, Equatable {
    case speech
    case typed
    /// A tapped answer to a page's question (IMP-25): a kid's turn, at most 120 characters.
    case choice
}

public enum Speaker: String, Codable, Sendable, Equatable {
    case parent
    case kid
}

/// The contract's `kid` object: `KidProfile` without its `id` (the server doesn't need it).
public struct StoryTurnKid: Codable, Sendable, Equatable {
    public let firstName: String
    public let readingLevel: ReadingLevel
    public let interests: [String]

    public init(firstName: String, readingLevel: ReadingLevel, interests: [String]) {
        self.firstName = firstName
        self.readingLevel = readingLevel
        self.interests = interests
    }

    public init(_ kid: KidProfile) {
        self.init(firstName: kid.firstName, readingLevel: kid.readingLevel, interests: kid.interests)
    }

    /// The kid as sent with this book: when the book has its own interests or setup answers,
    /// the profile's interests stay home, so they can't steer every book (IMP-24).
    public init(_ kid: KidProfile, for brief: StoryBrief) {
        self.init(firstName: kid.firstName, readingLevel: kid.readingLevel, interests: brief.hasOwnSetup ? [] : kid.interests)
    }
}

/// One entry of the contract's `pages` array: a prior page, by index and text only.
public struct StoryTurnPageRef: Codable, Sendable, Equatable {
    public let index: Int
    public let text: String

    public init(index: Int, text: String) {
        self.index = index
        self.text = text
    }

    public init(_ page: PageContent) {
        self.init(index: page.index, text: page.text)
    }
}

public struct StoryTurnInput: Codable, Sendable, Equatable {
    public let kind: InputKind
    public let speaker: Speaker
    public let text: String

    public init(kind: InputKind, speaker: Speaker, text: String) {
        self.kind = kind
        self.speaker = speaker
        self.text = text
    }
}

public struct StoryTurnRequest: Codable, Sendable, Equatable {
    public let mode: StoryTurnMode
    public let bookId: UUID
    public let kid: StoryTurnKid
    public let brief: StoryBrief
    public let settings: ParentSettings
    public let bible: StoryBible
    public let pages: [StoryTurnPageRef]
    /// Present for `mode: .path` when it follows a direction.
    public let input: StoryTurnInput?
    /// The page to write, for `mode: .path` and `mode: .page`.
    public let index: Int?

    public init(
        mode: StoryTurnMode, bookId: UUID, kid: StoryTurnKid, brief: StoryBrief, settings: ParentSettings,
        bible: StoryBible, pages: [StoryTurnPageRef], input: StoryTurnInput? = nil, index: Int? = nil
    ) {
        self.mode = mode
        self.bookId = bookId
        self.kid = kid
        self.brief = brief
        self.settings = settings
        self.bible = bible
        self.pages = pages
        self.input = input
        self.index = index
    }

    /// A `mode: "title"` request: the whole book's finished pages, no draft or input.
    public static func title(
        bookId: UUID, kid: StoryTurnKid, brief: StoryBrief, settings: ParentSettings, bible: StoryBible, pages: [StoryTurnPageRef]
    ) -> StoryTurnRequest {
        StoryTurnRequest(mode: .title, bookId: bookId, kid: kid, brief: brief, settings: settings, bible: bible, pages: pages)
    }
}

public struct StoryTurnPageResult: Codable, Sendable, Equatable {
    public let index: Int
    public let text: String
    public let artPrompt: String
    /// One question for the parent to ask about the page (PRD C3).
    public let question: String?
    /// Whether this page ends the story (`path` and `page` modes).
    public let isEnding: Bool?
    /// The question's kind (IMP-25); nil from older servers or when the question was gated out.
    public let questionKind: QuestionKind?
    /// Tap-to-steer answers to the question (IMP-25).
    public let choices: [StoryChoice]?

    public init(
        index: Int, text: String, artPrompt: String, question: String? = nil, isEnding: Bool? = nil,
        questionKind: QuestionKind? = nil, choices: [StoryChoice]? = nil
    ) {
        self.index = index
        self.text = text
        self.artPrompt = artPrompt
        self.question = question
        self.isEnding = isEnding
        self.questionKind = questionKind
        self.choices = choices
    }

    private enum CodingKeys: String, CodingKey { case index, text, artPrompt, question, isEnding, questionKind, choices }

    /// Tolerates a response that omits `question`, `isEnding` or the choices, and a question kind
    /// or choice this build doesn't know (the page still arrives, just without them).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try container.decode(Int.self, forKey: .index)
        text = try container.decode(String.self, forKey: .text)
        artPrompt = try container.decode(String.self, forKey: .artPrompt)
        question = try container.decodeIfPresent(String.self, forKey: .question)
        isEnding = try container.decodeIfPresent(Bool.self, forKey: .isEnding)
        questionKind = (try? container.decodeIfPresent(String.self, forKey: .questionKind)).flatMap { $0.flatMap(QuestionKind.init(rawValue:)) }
        choices = try? container.decodeIfPresent([StoryChoice].self, forKey: .choices)
    }
}

public enum StoryTurnAction: String, Codable, Sendable, Equatable {
    /// A page written by `path` or `page` mode.
    case page
    case none
}

public struct StoryTurnTimings: Codable, Sendable, Equatable {
    public let modelMs: Int
    public let safetyMs: Int

    public init(modelMs: Int, safetyMs: Int) {
        self.modelMs = modelMs
        self.safetyMs = safetyMs
    }

    private enum CodingKeys: String, CodingKey { case modelMs, safetyMs }

    /// Timings may arrive with fractions (JavaScript's `performance.now()`); round them.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modelMs = try container.decodeWholeNumber(forKey: .modelMs)
        safetyMs = try container.decodeWholeNumber(forKey: .safetyMs)
    }
}

extension KeyedDecodingContainer {
    /// Decodes a number that should be whole but may arrive with a fraction, rounding it.
    func decodeWholeNumber(forKey key: Key) throws -> Int {
        if let whole = try? decode(Int.self, forKey: key) { return whole }
        let value = try decode(Double.self, forKey: key)
        guard value.isFinite, abs(value) < Double(Int.max) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "\(value) isn't a usable whole number")
        }
        return Int(value.rounded())
    }
}

public struct StoryTurnResponse: Codable, Sendable, Equatable {
    public let action: StoryTurnAction
    /// Present unless `action == .none`.
    public let page: StoryTurnPageResult?
    public let bible: StoryBible
    public let parentNote: String?
    public let timings: StoryTurnTimings

    public init(action: StoryTurnAction, page: StoryTurnPageResult?, bible: StoryBible, parentNote: String?, timings: StoryTurnTimings) {
        self.action = action
        self.page = page
        self.bible = bible
        self.parentNote = parentNote
        self.timings = timings
    }
}

public struct StoryTitleResponse: Codable, Sendable, Equatable {
    public let title: String

    public init(title: String) {
        self.title = title
    }
}

// MARK: - art

public enum ArtKind: String, Codable, Sendable, Equatable {
    case page
    case cover
    case character
    case plate
    case cutout
    case drawing
}

public struct ArtRequest: Codable, Sendable, Equatable {
    public let bookId: UUID
    public let kind: ArtKind
    public let pageIndex: Int?
    public let version: Int?
    public let prompt: String
    public let characters: [Character]
    public let characterId: String?
    /// `kind: .drawing` only: the kid's own finger drawing, base64-encoded PNG or JPEG,
    /// ≤ 1.5 MB decoded (docs/CONTRACTS.md §3 `art`).
    public let drawing: String?

    public init(
        bookId: UUID, kind: ArtKind, pageIndex: Int? = nil, version: Int? = nil, prompt: String,
        characters: [Character] = [], characterId: String? = nil, drawing: String? = nil
    ) {
        self.bookId = bookId
        self.kind = kind
        self.pageIndex = pageIndex
        self.version = version
        self.prompt = prompt
        self.characters = characters
        self.characterId = characterId
        self.drawing = drawing
    }
}

public struct ArtResponse: Codable, Sendable, Equatable {
    public let path: String
    public let url: String
    public let width: Int
    public let height: Int
    public let placeholder: Bool
    public let ms: Int

    public init(path: String, url: String, width: Int, height: Int, placeholder: Bool, ms: Int) {
        self.path = path
        self.url = url
        self.width = width
        self.height = height
        self.placeholder = placeholder
        self.ms = ms
    }

    private enum CodingKeys: String, CodingKey { case path, url, width, height, placeholder, ms }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        url = try container.decode(String.self, forKey: .url)
        width = try container.decodeWholeNumber(forKey: .width)
        height = try container.decodeWholeNumber(forKey: .height)
        placeholder = try container.decode(Bool.self, forKey: .placeholder)
        ms = try container.decodeWholeNumber(forKey: .ms)
    }
}

// MARK: - motion-prompt

public struct MotionPromptRequest: Codable, Sendable, Equatable {
    public let bookId: UUID
    public let pageIndex: Int
    public let text: String
    public let stillPath: String

    public init(bookId: UUID, pageIndex: Int, text: String, stillPath: String) {
        self.bookId = bookId
        self.pageIndex = pageIndex
        self.text = text
        self.stillPath = stillPath
    }
}

// The response is exactly `MotionParts` (Domain/Models.swift).

// MARK: - moderate

public struct ModerateRequest: Codable, Sendable, Equatable {
    public let text: String?
    public let imageBase64: String?
    public let mimeType: String?

    private init(text: String?, imageBase64: String?, mimeType: String?) {
        self.text = text
        self.imageBase64 = imageBase64
        self.mimeType = mimeType
    }

    public static func text(_ text: String) -> ModerateRequest {
        ModerateRequest(text: text, imageBase64: nil, mimeType: nil)
    }

    public static func image(base64: String, mimeType: String) -> ModerateRequest {
        ModerateRequest(text: nil, imageBase64: base64, mimeType: mimeType)
    }
}

public struct ModerateResponse: Codable, Sendable, Equatable {
    public let flagged: Bool
    public let categories: [String]

    public init(flagged: Bool, categories: [String]) {
        self.flagged = flagged
        self.categories = categories
    }
}

// MARK: - tts

public struct TTSRequest: Codable, Sendable, Equatable {
    public let text: String
    public let voice: String

    public init(text: String, voice: String) {
        self.text = text
        self.voice = voice
    }
}

public struct TTSResponse: Codable, Sendable, Equatable {
    public let audioBase64: String
    public let format: String

    public init(audioBase64: String, format: String) {
        self.audioBase64 = audioBase64
        self.format = format
    }
}

// MARK: - stt-token

public struct STTTokenResponse: Codable, Sendable, Equatable {
    public let clientSecret: String
    public let expiresAt: Double
    public let model: String

    public init(clientSecret: String, expiresAt: Double, model: String) {
        self.clientSecret = clientSecret
        self.expiresAt = expiresAt
        self.model = model
    }
}

// MARK: - reactor-token

public enum ReactorTokenAction: String, Codable, Sendable, Equatable {
    case mint
    case report
    case cleanup
}

public struct ReactorTokenRequest: Codable, Sendable, Equatable {
    public let action: ReactorTokenAction
    /// Present only for `action == .report`.
    public let sessionId: String?

    private init(action: ReactorTokenAction, sessionId: String?) {
        self.action = action
        self.sessionId = sessionId
    }

    public static func mint() -> ReactorTokenRequest { ReactorTokenRequest(action: .mint, sessionId: nil) }
    public static func report(sessionId: String) -> ReactorTokenRequest { ReactorTokenRequest(action: .report, sessionId: sessionId) }
    public static func cleanup() -> ReactorTokenRequest { ReactorTokenRequest(action: .cleanup, sessionId: nil) }
}

public struct ReactorMintResponse: Codable, Sendable, Equatable {
    public let jwt: String
    /// Unix seconds. Older `reactor-token` deployments sent milliseconds, so any value
    /// above 1e12 (which as seconds would be the year 33658) is read as milliseconds.
    public let expiresAt: Double

    public init(jwt: String, expiresAt: Double) {
        self.jwt = jwt
        self.expiresAt = Self.seconds(fromEither: expiresAt)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(jwt: try container.decode(String.self, forKey: .jwt), expiresAt: try container.decode(Double.self, forKey: .expiresAt))
    }

    private enum CodingKeys: String, CodingKey { case jwt, expiresAt }

    private static let millisecondsThreshold = 1e12

    private static func seconds(fromEither value: Double) -> Double {
        value > millisecondsThreshold ? value / 1000 : value
    }
}

public struct ReactorCleanupResponse: Codable, Sendable, Equatable {
    public let ended: Int

    public init(ended: Int) {
        self.ended = ended
    }
}

// MARK: - reactor-sessions (admin-only; the app never calls it, but the run-book's wire shape lives here too)

public enum ReactorSessionsAction: String, Codable, Sendable, Equatable {
    case list
    case kill
}

public struct ReactorSessionsRequest: Codable, Sendable, Equatable {
    public let action: ReactorSessionsAction

    public init(action: ReactorSessionsAction) {
        self.action = action
    }
}

public struct ReactorSessionInfo: Codable, Sendable, Equatable {
    public let sessionId: String
    public let state: String

    public init(sessionId: String, state: String) {
        self.sessionId = sessionId
        self.state = state
    }
}

public struct ReactorSessionsListResponse: Codable, Sendable, Equatable {
    public let open: [ReactorSessionInfo]

    public init(open: [ReactorSessionInfo]) {
        self.open = open
    }
}

public struct ReactorSessionsKillResponse: Codable, Sendable, Equatable {
    public let ended: Int

    public init(ended: Int) {
        self.ended = ended
    }
}
