import Foundation
import Testing
@testable import PopKit

/// Covers `HTTPPopServer`: each protocol method calls the right function name with
/// the contract's headers, and a `.unauthorized` envelope error triggers one
/// refresh-and-retry (docs/CONTRACTS.md §3, ROADMAP §2 server access model).
struct PopServerTests {
    private let baseURL = URL(string: "https://pop.example")!

    private func auth(accessToken: String = "tok-0") -> AnonymousAuth {
        let store = InMemorySessionStore(initial: StoredSession(
            accessToken: accessToken, refreshToken: "ref-0", expiresAt: Date.distantFuture, userId: "u-1"
        ))
        let transport = FakeHTTPTransport { _ in Issue.record("auth should not need the network here"); fatalError() }
        return AnonymousAuth(supabaseURL: baseURL, publishableKey: "pub-key", transport: transport, store: store)
    }

    @Test func storyTurnPostsToStoryTurnWithContractHeaders() async throws {
        let transport = FakeHTTPTransport { request in
            #expect(request.url?.absoluteString == "https://pop.example/functions/v1/story-turn")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "apikey") == "pub-key")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok-0")
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any]
            #expect(body?["mode"] as? String == "path")
            return (Data(#"""
            {"ok":true,"data":{"action":"page","page":{"index":0,"text":"Once upon a time","artPrompt":"a fox"},
            "bible":{"title":null,"setting":"","characters":[],"directions":[]},"parentNote":null,"timings":{"modelMs":1,"safetyMs":1}}}
            """#.utf8), .fake(status: 200, url: request.url!))
        }
        let server = HTTPPopServer(supabaseURL: baseURL, publishableKey: "pub-key", transport: transport, auth: auth())
        let request = StoryTurnRequest(
            mode: .path, bookId: UUID(), kid: StoryTurnKid(firstName: "Sara", readingLevel: .listener, interests: []),
            brief: StoryBrief(interests: []), settings: ParentSettings(), bible: .empty, pages: [],
            input: StoryTurnInput(kind: .typed, speaker: .parent, text: "begin"), index: 0
        )
        let response = try await server.storyTurn(request)
        #expect(response.action == .page)
        #expect(response.page?.text == "Once upon a time")
    }

    @Test func storyTitlePostsToStoryTurnAndDecodesTheTitleShape() async throws {
        let transport = FakeHTTPTransport { request in
            (Data(#"{"ok":true,"data":{"title":"Rex Learns to Share"}}"#.utf8), .fake(status: 200, url: request.url!))
        }
        let server = HTTPPopServer(supabaseURL: baseURL, publishableKey: "pub-key", transport: transport, auth: auth())
        let response = try await server.storyTitle(.title(
            bookId: UUID(), kid: StoryTurnKid(firstName: "Sara", readingLevel: .listener, interests: []),
            brief: StoryBrief(interests: []), settings: ParentSettings(), bible: .empty, pages: []
        ))
        #expect(response.title == "Rex Learns to Share")
    }

    @Test func artPostsToArt() async throws {
        let transport = FakeHTTPTransport { request in
            #expect(request.url?.absoluteString.hasSuffix("/functions/v1/art") == true)
            return (Data(#"{"ok":true,"data":{"path":"u/b/p0.png","url":"https://x","width":1344,"height":768,"placeholder":false,"ms":1}}"#.utf8), .fake(status: 200, url: request.url!))
        }
        let server = HTTPPopServer(supabaseURL: baseURL, publishableKey: "pub-key", transport: transport, auth: auth())
        let response = try await server.art(ArtRequest(bookId: UUID(), kind: .page, pageIndex: 0, version: 1, prompt: "a fox"))
        #expect(response.path == "u/b/p0.png")
    }

    @Test func motionPromptPostsToMotionPromptAndDecodesMotionParts() async throws {
        let transport = FakeHTTPTransport { request in
            #expect(request.url?.absoluteString.hasSuffix("/functions/v1/motion-prompt") == true)
            return (Data(#"{"ok":true,"data":{"scene":"a meadow","motion":"grass sways"}}"#.utf8), .fake(status: 200, url: request.url!))
        }
        let server = HTTPPopServer(supabaseURL: baseURL, publishableKey: "pub-key", transport: transport, auth: auth())
        let parts = try await server.motionPrompt(MotionPromptRequest(bookId: UUID(), pageIndex: 0, text: "text", stillPath: "still.png"))
        #expect(parts == MotionParts(scene: "a meadow", motion: "grass sways"))
    }

    @Test func moderateTTSAndSTTTokenPostToTheirOwnFunctions() async throws {
        let transport = FakeHTTPTransport { request in
            switch request.url?.lastPathComponent {
            case "moderate": return (Data(#"{"ok":true,"data":{"flagged":false,"categories":[]}}"#.utf8), .fake(status: 200, url: request.url!))
            case "tts": return (Data(#"{"ok":true,"data":{"audioBase64":"AAA=","format":"mp3"}}"#.utf8), .fake(status: 200, url: request.url!))
            case "stt-token": return (Data(#"{"ok":true,"data":{"clientSecret":"sec","expiresAt":123,"model":"gpt"}}"#.utf8), .fake(status: 200, url: request.url!))
            default: Issue.record("unexpected function \(request.url?.absoluteString ?? "")"); fatalError()
            }
        }
        let server = HTTPPopServer(supabaseURL: baseURL, publishableKey: "pub-key", transport: transport, auth: auth())
        #expect(try await server.moderate(.text("hi")).flagged == false)
        #expect(try await server.tts(TTSRequest(text: "hi", voice: "v1")).format == "mp3")
        #expect(try await server.sttToken().clientSecret == "sec")
    }

    @Test func reactorTokenActionsPostToReactorToken() async throws {
        let transport = FakeHTTPTransport { request in
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any]
            switch body?["action"] as? String {
            case "mint": return (Data(#"{"ok":true,"data":{"jwt":"j","expiresAt":1}}"#.utf8), .fake(status: 200, url: request.url!))
            case "report": return (Data(#"{"ok":true,"data":{}}"#.utf8), .fake(status: 200, url: request.url!))
            case "cleanup": return (Data(#"{"ok":true,"data":{"ended":2}}"#.utf8), .fake(status: 200, url: request.url!))
            default: Issue.record("unexpected action"); fatalError()
            }
        }
        let server = HTTPPopServer(supabaseURL: baseURL, publishableKey: "pub-key", transport: transport, auth: auth())
        #expect(try await server.reactorMint().jwt == "j")
        try await server.reactorReport(sessionId: "s-1")
        #expect(try await server.reactorCleanup().ended == 2)
    }

    @Test func anUnauthorizedEnvelopeErrorRefreshesTheTokenAndRetriesOnce() async throws {
        let functionsTransport = FakeHTTPTransport { request in
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer tok-old" {
                return (Data(#"{"ok":false,"error":{"code":"unauthorized","message":"expired"}}"#.utf8), .fake(status: 401, url: request.url!))
            }
            return (Data(#"{"ok":true,"data":{"flagged":false,"categories":[]}}"#.utf8), .fake(status: 200, url: request.url!))
        }
        let authTransport = FakeHTTPTransport { request in
            (Data(#"{"access_token":"tok-new","refresh_token":"ref-new","expires_in":3600,"user":{"id":"u-1"}}"#.utf8), .fake(status: 200, url: request.url!))
        }
        let store = InMemorySessionStore(initial: StoredSession(accessToken: "tok-old", refreshToken: "ref-old", expiresAt: .distantFuture, userId: "u-1"))
        let auth = AnonymousAuth(supabaseURL: baseURL, publishableKey: "pub-key", transport: authTransport, store: store)
        let server = HTTPPopServer(supabaseURL: baseURL, publishableKey: "pub-key", transport: functionsTransport, auth: auth)

        let response = try await server.moderate(.text("hi"))
        #expect(response.flagged == false)
        let requestCount = await functionsTransport.requestCount
        #expect(requestCount == 2)
    }

    @Test func anUnrecoverableServerErrorIsThrownAsIs() async throws {
        let transport = FakeHTTPTransport { request in
            (Data(#"{"ok":false,"error":{"code":"unsafe","message":"let's try something else"}}"#.utf8), .fake(status: 422, url: request.url!))
        }
        let server = HTTPPopServer(supabaseURL: baseURL, publishableKey: "pub-key", transport: transport, auth: auth())
        await #expect(throws: ServerError.unsafe("let's try something else")) {
            _ = try await server.moderate(.text("hi"))
        }
    }

    // MARK: - IMP-10: timeouts and non-envelope gateway replies

    @Test func eachFunctionCallCarriesItsOwnTimeout() async throws {
        let transport = FakeHTTPTransport { request in
            let body: String = switch request.url?.lastPathComponent {
            case "story-turn": #"{"ok":true,"data":{"title":"T"}}"#
            case "art": #"{"ok":true,"data":{"path":"p","url":"https://x","width":1,"height":1,"placeholder":false,"ms":1}}"#
            case "motion-prompt": #"{"ok":true,"data":{"scene":"s","motion":"m"}}"#
            default: #"{"ok":true,"data":{"flagged":false,"categories":[]}}"#
            }
            return (Data(body.utf8), .fake(status: 200, url: request.url!))
        }
        let server = HTTPPopServer(supabaseURL: baseURL, publishableKey: "pub-key", transport: transport, auth: auth())
        let kid = StoryTurnKid(firstName: "Sara", readingLevel: .listener, interests: [])
        _ = try await server.storyTitle(.title(bookId: UUID(), kid: kid, brief: StoryBrief(interests: []), settings: ParentSettings(), bible: .empty, pages: []))
        _ = try await server.art(ArtRequest(bookId: UUID(), kind: .page, pageIndex: 0, version: 1, prompt: "a fox"))
        _ = try await server.motionPrompt(MotionPromptRequest(bookId: UUID(), pageIndex: 0, text: "t", stillPath: "s.png"))
        _ = try await server.moderate(.text("hi"))

        let timeouts = await transport.requests.map { ($0.url!.lastPathComponent, $0.timeoutInterval) }
        #expect(timeouts.map(\.0) == ["story-turn", "art", "motion-prompt", "moderate"])
        #expect(timeouts.map(\.1) == [25, 45, 20, 8])
    }

    @Test func aNonEnvelope5xxFromTheGatewayIsAnUpstreamError() async throws {
        let transport = FakeHTTPTransport.json(502, body: "<html>Bad Gateway</html>")
        let server = HTTPPopServer(supabaseURL: baseURL, publishableKey: "pub-key", transport: transport, auth: auth())
        await #expect(throws: ServerError.upstream("HTTP 502 from moderate")) {
            _ = try await server.moderate(.text("hi"))
        }
    }

    @Test func aNonEnvelope429IsRateLimited() async throws {
        let transport = FakeHTTPTransport.json(429, body: #"{"message":"too many"}"#)
        let server = HTTPPopServer(supabaseURL: baseURL, publishableKey: "pub-key", transport: transport, auth: auth())
        await #expect(throws: ServerError.rateLimited("HTTP 429 from moderate")) {
            _ = try await server.moderate(.text("hi"))
        }
    }

    @Test func aNonEnvelope401FromTheGatewayStillRefreshesAndRetries() async throws {
        let functionsTransport = FakeHTTPTransport { request in
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer tok-old" {
                return (Data(#"{"code":401,"message":"Invalid JWT"}"#.utf8), .fake(status: 401, url: request.url!))
            }
            return (Data(#"{"ok":true,"data":{"flagged":false,"categories":[]}}"#.utf8), .fake(status: 200, url: request.url!))
        }
        let authTransport = FakeHTTPTransport { request in
            (Data(#"{"access_token":"tok-new","refresh_token":"ref-new","expires_in":3600,"user":{"id":"u-1"}}"#.utf8), .fake(status: 200, url: request.url!))
        }
        let store = InMemorySessionStore(initial: StoredSession(accessToken: "tok-old", refreshToken: "ref-old", expiresAt: .distantFuture, userId: "u-1"))
        let auth = AnonymousAuth(supabaseURL: baseURL, publishableKey: "pub-key", transport: authTransport, store: store)
        let server = HTTPPopServer(supabaseURL: baseURL, publishableKey: "pub-key", transport: functionsTransport, auth: auth)

        #expect(try await server.moderate(.text("hi")).flagged == false)
        #expect(await functionsTransport.requestCount == 2)
        #expect(await authTransport.lastRequest?.timeoutInterval == 15)
    }

    @Test func a200WithAnUnexpectedBodyIsStillADecodingError() async throws {
        let transport = FakeHTTPTransport.json(200, body: "not json")
        let server = HTTPPopServer(supabaseURL: baseURL, publishableKey: "pub-key", transport: transport, auth: auth())
        await #expect {
            _ = try await server.moderate(.text("hi"))
        } throws: { error in
            if case .decoding = error as? ServerError { return true }
            return false
        }
    }
}
