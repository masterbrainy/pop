import Foundation
@testable import PopKit

/// A `PopServer` other modules' tests can script directly, without any networking —
/// PagePipeline, StoryEngine call-site, and SessionController tests all use this
/// instead of `HTTPPopServer` + `FakeHTTPTransport`.
actor FakePopServer: PopServer {
    var storyTurnHandler: (@Sendable (StoryTurnRequest) async throws -> StoryTurnResponse)?
    var storyTitleHandler: (@Sendable (StoryTurnRequest) async throws -> StoryTitleResponse)?
    var artHandler: (@Sendable (ArtRequest) async throws -> ArtResponse)?
    var motionPromptHandler: (@Sendable (MotionPromptRequest) async throws -> MotionParts)?
    var moderateHandler: (@Sendable (ModerateRequest) async throws -> ModerateResponse)?
    var ttsHandler: (@Sendable (TTSRequest) async throws -> TTSResponse)?
    var sttTokenHandler: (@Sendable () async throws -> STTTokenResponse)?
    var reactorMintHandler: (@Sendable () async throws -> ReactorMintResponse)?
    var reactorReportHandler: (@Sendable (String) async throws -> Void)?
    var reactorCleanupHandler: (@Sendable () async throws -> ReactorCleanupResponse)?

    private(set) var storyTurnCalls: [StoryTurnRequest] = []
    private(set) var artCalls: [ArtRequest] = []
    private(set) var motionPromptCalls: [MotionPromptRequest] = []

    init() {}

    func storyTurn(_ request: StoryTurnRequest) async throws -> StoryTurnResponse {
        storyTurnCalls.append(request)
        guard let handler = storyTurnHandler else { fatalError("FakePopServer.storyTurnHandler not set") }
        return try await handler(request)
    }

    func storyTitle(_ request: StoryTurnRequest) async throws -> StoryTitleResponse {
        guard let handler = storyTitleHandler else { fatalError("FakePopServer.storyTitleHandler not set") }
        return try await handler(request)
    }

    func art(_ request: ArtRequest) async throws -> ArtResponse {
        artCalls.append(request)
        guard let handler = artHandler else { fatalError("FakePopServer.artHandler not set") }
        return try await handler(request)
    }

    func motionPrompt(_ request: MotionPromptRequest) async throws -> MotionParts {
        motionPromptCalls.append(request)
        guard let handler = motionPromptHandler else { fatalError("FakePopServer.motionPromptHandler not set") }
        return try await handler(request)
    }

    func moderate(_ request: ModerateRequest) async throws -> ModerateResponse {
        guard let handler = moderateHandler else { fatalError("FakePopServer.moderateHandler not set") }
        return try await handler(request)
    }

    func tts(_ request: TTSRequest) async throws -> TTSResponse {
        guard let handler = ttsHandler else { fatalError("FakePopServer.ttsHandler not set") }
        return try await handler(request)
    }

    func sttToken() async throws -> STTTokenResponse {
        guard let handler = sttTokenHandler else { fatalError("FakePopServer.sttTokenHandler not set") }
        return try await handler()
    }

    func reactorMint() async throws -> ReactorMintResponse {
        guard let handler = reactorMintHandler else { fatalError("FakePopServer.reactorMintHandler not set") }
        return try await handler()
    }

    func reactorReport(sessionId: String) async throws {
        guard let handler = reactorReportHandler else { fatalError("FakePopServer.reactorReportHandler not set") }
        try await handler(sessionId)
    }

    func reactorCleanup() async throws -> ReactorCleanupResponse {
        guard let handler = reactorCleanupHandler else { fatalError("FakePopServer.reactorCleanupHandler not set") }
        return try await handler()
    }

    // MARK: - convenience setters (actor-isolated, so tests `await` these)

    func onStoryTurn(_ handler: @escaping @Sendable (StoryTurnRequest) async throws -> StoryTurnResponse) {
        storyTurnHandler = handler
    }

    func onArt(_ handler: @escaping @Sendable (ArtRequest) async throws -> ArtResponse) {
        artHandler = handler
    }

    func onMotionPrompt(_ handler: @escaping @Sendable (MotionPromptRequest) async throws -> MotionParts) {
        motionPromptHandler = handler
    }

    func onReactorMint(_ handler: @escaping @Sendable () async throws -> ReactorMintResponse) {
        reactorMintHandler = handler
    }
}
