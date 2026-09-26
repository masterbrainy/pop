import Foundation
import Testing
@testable import PopKit

/// Covers `AnonymousAuth`: anonymous sign-in through Supabase GoTrue, refreshing
/// before expiry, falling back to a fresh sign-in when the refresh token is
/// rejected, and persisting through the injectable `SessionStore`.
struct AnonymousAuthTests {
    private let baseURL = URL(string: "https://pop.example")!
    private let fixedNow = Date(timeIntervalSince1970: 1_000_000)

    private func goTrueBody(accessToken: String, refreshToken: String, expiresIn: Double = 3600, userId: String = "u-1") -> String {
        #"{"access_token":"\#(accessToken)","refresh_token":"\#(refreshToken)","expires_in":\#(expiresIn),"user":{"id":"\#(userId)"}}"#
    }

    @Test func signsInAnonymouslyWhenNothingIsStored() async throws {
        let transport = FakeHTTPTransport { request in
            #expect(request.url?.path == "/auth/v1/signup")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "apikey") == "pub-key")
            let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
            #expect(body?.isEmpty == true)
            return (Data(self.goTrueBody(accessToken: "tok-0", refreshToken: "ref-0").utf8), .fake(status: 200, url: request.url!))
        }
        let auth = AnonymousAuth(supabaseURL: baseURL, publishableKey: "pub-key", transport: transport, store: InMemorySessionStore(), now: { self.fixedNow })

        let token = try await auth.accessToken()
        #expect(token == "tok-0")
        let userId = await auth.userId
        #expect(userId == "u-1")
    }

    @Test func reusesAStoredSessionThatIsNotNearExpiry() async throws {
        let transport = FakeHTTPTransport { _ in Issue.record("should not call the network"); fatalError() }
        let farFuture = fixedNow.addingTimeInterval(3600)
        let store = InMemorySessionStore(initial: StoredSession(accessToken: "cached", refreshToken: "ref", expiresAt: farFuture, userId: "u-1"))
        let auth = AnonymousAuth(supabaseURL: baseURL, publishableKey: "pub-key", transport: transport, store: store, now: { self.fixedNow })

        let token = try await auth.accessToken()
        #expect(token == "cached")
        let count = await transport.requestCount
        #expect(count == 0)
    }

    @Test func refreshesASessionThatIsNearExpiry() async throws {
        let transport = FakeHTTPTransport { request in
            #expect(request.url?.path == "/auth/v1/token")
            #expect(request.url?.query == "grant_type=refresh_token")
            let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
            #expect(body?["refresh_token"] as? String == "ref-old")
            return (Data(self.goTrueBody(accessToken: "tok-new", refreshToken: "ref-new").utf8), .fake(status: 200, url: request.url!))
        }
        let almostExpired = fixedNow.addingTimeInterval(10)
        let store = InMemorySessionStore(initial: StoredSession(accessToken: "tok-old", refreshToken: "ref-old", expiresAt: almostExpired, userId: "u-1"))
        let auth = AnonymousAuth(supabaseURL: baseURL, publishableKey: "pub-key", transport: transport, store: store, now: { self.fixedNow })

        let token = try await auth.accessToken()
        #expect(token == "tok-new")
        let stored = await store.load()
        #expect(stored?.accessToken == "tok-new")
        #expect(stored?.refreshToken == "ref-new")
    }

    @Test func fallsBackToAFreshSignInWhenTheRefreshTokenIsRejected() async throws {
        let transport = FakeHTTPTransport { request in
            if request.url?.path == "/auth/v1/token" {
                return (Data(#"{"error":"invalid_grant"}"#.utf8), .fake(status: 401, url: request.url!))
            }
            return (Data(self.goTrueBody(accessToken: "tok-fresh", refreshToken: "ref-fresh").utf8), .fake(status: 200, url: request.url!))
        }
        let almostExpired = fixedNow.addingTimeInterval(10)
        let store = InMemorySessionStore(initial: StoredSession(accessToken: "tok-old", refreshToken: "ref-old", expiresAt: almostExpired, userId: "u-1"))
        let auth = AnonymousAuth(supabaseURL: baseURL, publishableKey: "pub-key", transport: transport, store: store, now: { self.fixedNow })

        let token = try await auth.accessToken()
        #expect(token == "tok-fresh")
    }

    @Test func forcedRefreshAlwaysHitsTheNetworkEvenWithAFreshSession() async throws {
        let transport = FakeHTTPTransport { request in
            (Data(self.goTrueBody(accessToken: "tok-forced", refreshToken: "ref-forced").utf8), .fake(status: 200, url: request.url!))
        }
        let farFuture = fixedNow.addingTimeInterval(3600)
        let store = InMemorySessionStore(initial: StoredSession(accessToken: "cached", refreshToken: "ref", expiresAt: farFuture, userId: "u-1"))
        let auth = AnonymousAuth(supabaseURL: baseURL, publishableKey: "pub-key", transport: transport, store: store, now: { self.fixedNow })

        let token = try await auth.refreshedAccessToken()
        #expect(token == "tok-forced")
    }
}
