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
    case turn
    case title
}

public enum InputKind: String, Codable, Sendable, Equatable {
    case speech
    case typed
    case continueStory = "continue"
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

public struct StoryTurnCurrent: Codable, Sendable, Equatable {
    public let index: Int
    /// The draft so far; may be empty.
    public let text: String

    public init(index: Int, text: String) {
        self.index = index
        self.text = text
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
    /// Present for `mode: .turn`; omitted for `mode: .title`, which only needs the finished pages.
    public let current: StoryTurnCurrent?
    /// Present for `mode: .turn`; omitted for `mode: .title`.
    public let input: StoryTurnInput?

    public init(
        mode: StoryTurnMode, bookId: UUID, kid: StoryTurnKid, brief: StoryBrief, settings: ParentSettings,
        bible: StoryBible, pages: [StoryTurnPageRef], current: StoryTurnCurrent? = nil, input: StoryTurnInput? = nil
    ) {
        self.mode = mode
        self.bookId = bookId
        self.kid = kid
        self.brief = brief
        self.settings = settings
        self.bible = bible
        self.pages = pages
        self.current = current
        self.input = input
    }

    /// A `mode: "turn"` request.
    public static func turn(
        bookId: UUID, kid: StoryTurnKid, brief: StoryBrief, settings: ParentSettings, bible: StoryBible,
        pages: [StoryTurnPageRef], current: StoryTurnCurrent, input: StoryTurnInput
    ) -> StoryTurnRequest {
        StoryTurnRequest(mode: .turn, bookId: bookId, kid: kid, brief: brief, settings: settings, bible: bible, pages: pages, current: current, input: input)
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
    public let breakSuggested: Bool

    public init(index: Int, text: String, artPrompt: String, breakSuggested: Bool) {
        self.index = index
        self.text = text
        self.artPrompt = artPrompt
        self.breakSuggested = breakSuggested
    }
}

public enum StoryTurnAction: String, Codable, Sendable, Equatable {
    case append
    case newPage = "new_page"
    case reviseCurrent = "revise_current"
    case none
}

public struct StoryTurnTimings: Codable, Sendable, Equatable {
    public let modelMs: Int
    public let safetyMs: Int

    public init(modelMs: Int, safetyMs: Int) {
        self.modelMs = modelMs
        self.safetyMs = safetyMs
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
}

public struct ArtRequest: Codable, Sendable, Equatable {
    public let bookId: UUID
    public let kind: ArtKind
    public let pageIndex: Int?
    public let version: Int?
    public let prompt: String
    public let characters: [Character]
    public let characterId: String?

    public init(bookId: UUID, kind: ArtKind, pageIndex: Int? = nil, version: Int? = nil, prompt: String, characters: [Character] = [], characterId: String? = nil) {
        self.bookId = bookId
        self.kind = kind
        self.pageIndex = pageIndex
        self.version = version
        self.prompt = prompt
        self.characters = characters
        self.characterId = characterId
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
    public let expiresAt: Double

    public init(jwt: String, expiresAt: Double) {
        self.jwt = jwt
        self.expiresAt = expiresAt
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
