import Foundation

/// The transport `HTTPPopServer` sends requests through — `URLSession` in the app,
/// a scripted fake in tests.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// `URLSession` behind `HTTPTransport`, for the real app.
public struct URLSessionHTTPTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ServerError.transport("response was not HTTP")
        }
        return (data, http)
    }
}

/// One async method per Edge Function in docs/CONTRACTS.md §3. `reactor-sessions` is
/// admin-only and the app never calls it, so it isn't part of this surface.
public protocol PopServer: Sendable {
    func storyTurn(_ request: StoryTurnRequest) async throws -> StoryTurnResponse
    func storyTitle(_ request: StoryTurnRequest) async throws -> StoryTitleResponse
    func art(_ request: ArtRequest) async throws -> ArtResponse
    func motionPrompt(_ request: MotionPromptRequest) async throws -> MotionParts
    func moderate(_ request: ModerateRequest) async throws -> ModerateResponse
    func tts(_ request: TTSRequest) async throws -> TTSResponse
    func sttToken() async throws -> STTTokenResponse
    func reactorMint() async throws -> ReactorMintResponse
    func reactorReport(sessionId: String) async throws
    func reactorCleanup() async throws -> ReactorCleanupResponse
}

/// Calls `{supabaseURL}/functions/v1/{name}` with `apikey` and a bearer access token
/// from `AnonymousAuth` (ROADMAP §2). A server `unauthorized` reply triggers one
/// forced refresh and retry before giving up.
public actor HTTPPopServer: PopServer {
    private let baseURL: URL
    private let publishableKey: String
    private let transport: HTTPTransport
    private let auth: AnonymousAuth

    public init(supabaseURL: URL, publishableKey: String, transport: HTTPTransport, auth: AnonymousAuth) {
        self.baseURL = supabaseURL
        self.publishableKey = publishableKey
        self.transport = transport
        self.auth = auth
    }

    public func storyTurn(_ request: StoryTurnRequest) async throws -> StoryTurnResponse {
        try await call("story-turn", request)
    }

    public func storyTitle(_ request: StoryTurnRequest) async throws -> StoryTitleResponse {
        try await call("story-turn", request)
    }

    public func art(_ request: ArtRequest) async throws -> ArtResponse {
        try await call("art", request)
    }

    public func motionPrompt(_ request: MotionPromptRequest) async throws -> MotionParts {
        try await call("motion-prompt", request)
    }

    public func moderate(_ request: ModerateRequest) async throws -> ModerateResponse {
        try await call("moderate", request)
    }

    public func tts(_ request: TTSRequest) async throws -> TTSResponse {
        try await call("tts", request)
    }

    public func sttToken() async throws -> STTTokenResponse {
        try await call("stt-token", EmptyPayload())
    }

    public func reactorMint() async throws -> ReactorMintResponse {
        try await call("reactor-token", ReactorTokenRequest.mint())
    }

    public func reactorReport(sessionId: String) async throws {
        let _: EmptyPayload = try await call("reactor-token", ReactorTokenRequest.report(sessionId: sessionId))
    }

    public func reactorCleanup() async throws -> ReactorCleanupResponse {
        try await call("reactor-token", ReactorTokenRequest.cleanup())
    }

    private func call<Req: Encodable, Res: Decodable>(_ name: String, _ body: Req) async throws -> Res {
        let token = try await auth.accessToken()
        let (data, _) = try await perform(name, body, accessToken: token)

        switch Envelope.decode(data, as: Res.self) {
        case .success(let value):
            return value
        case .failure(.unauthorized):
            let refreshed = try await auth.refreshedAccessToken()
            let (retryData, _) = try await perform(name, body, accessToken: refreshed)
            switch Envelope.decode(retryData, as: Res.self) {
            case .success(let value): return value
            case .failure(let error): throw error
            }
        case .failure(let error):
            throw error
        }
    }

    private func perform<Req: Encodable>(_ name: String, _ body: Req, accessToken: String) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: baseURL.appendingPathComponent("functions/v1/\(name)"))
        request.httpMethod = "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw ServerError.decoding("\(error)")
        }
        do {
            return try await transport.send(request)
        } catch let error as ServerError {
            throw error
        } catch {
            throw ServerError.transport("\(error)")
        }
    }
}
