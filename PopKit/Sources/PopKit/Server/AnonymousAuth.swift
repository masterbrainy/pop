import Foundation

/// A signed-in session, persisted between launches so the app doesn't sign in
/// anonymously again every time (ROADMAP §2 server access model).
public struct StoredSession: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date
    public let userId: String

    public init(accessToken: String, refreshToken: String, expiresAt: Date, userId: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.userId = userId
    }
}

/// Where `AnonymousAuth` keeps the current session. The app backs this with disk;
/// tests use `InMemorySessionStore`.
public protocol SessionStore: Sendable {
    func load() async -> StoredSession?
    func save(_ session: StoredSession?) async
}

public actor InMemorySessionStore: SessionStore {
    private var session: StoredSession?

    public init(initial: StoredSession? = nil) {
        self.session = initial
    }

    public func load() async -> StoredSession? { session }

    public func save(_ session: StoredSession?) async {
        self.session = session
    }
}

/// Signs in anonymously with Supabase GoTrue (`POST {url}/auth/v1/signup` with body
/// `{}`), refreshes before the token expires (`POST /auth/v1/token?grant_type=refresh_token`),
/// and falls back to a fresh sign-in if the refresh token is itself rejected. Persists
/// through the injectable `SessionStore` (ROADMAP §2).
public actor AnonymousAuth {
    /// Refresh this long before the access token actually expires, so a call that
    /// starts now doesn't race the expiry.
    private static let refreshLeadTime: TimeInterval = 60

    private let baseURL: URL
    private let publishableKey: String
    private let transport: HTTPTransport
    private let store: SessionStore
    private let now: @Sendable () -> Date
    private var session: StoredSession?

    public init(
        supabaseURL: URL, publishableKey: String, transport: HTTPTransport, store: SessionStore,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.baseURL = supabaseURL
        self.publishableKey = publishableKey
        self.transport = transport
        self.store = store
        self.now = now
    }

    public var userId: String? {
        get async {
            if let session { return session.userId }
            return await store.load()?.userId
        }
    }

    /// A valid access token: the cached one if it isn't near expiry, otherwise a refreshed
    /// (or freshly signed-in) one.
    public func accessToken() async throws -> String {
        if let current = await currentSession(), !isNearExpiry(current) {
            return current.accessToken
        }
        return try await refreshedAccessToken()
    }

    /// Always hits the network: refreshes the current session, or signs in anonymously
    /// if there is none or the refresh token is rejected. Used both for a near-expiry
    /// token and to retry once after a server `unauthorized` reply.
    public func refreshedAccessToken() async throws -> String {
        let fresh: StoredSession
        if let current = await currentSession() {
            do {
                fresh = try await refresh(refreshToken: current.refreshToken)
            } catch {
                fresh = try await signUpAnonymously()
            }
        } else {
            fresh = try await signUpAnonymously()
        }
        session = fresh
        await store.save(fresh)
        return fresh.accessToken
    }

    private func currentSession() async -> StoredSession? {
        if let session { return session }
        let restored = await store.load()
        session = restored
        return restored
    }

    private func isNearExpiry(_ session: StoredSession) -> Bool {
        now() >= session.expiresAt.addingTimeInterval(-Self.refreshLeadTime)
    }

    private func signUpAnonymously() async throws -> StoredSession {
        try await goTrueCall(path: "auth/v1/signup", query: nil, body: EmptyPayload())
    }

    private func refresh(refreshToken: String) async throws -> StoredSession {
        try await goTrueCall(path: "auth/v1/token", query: "grant_type=refresh_token", body: RefreshBody(refreshToken: refreshToken))
    }

    private func goTrueCall<Body: Encodable>(path: String, query: String?, body: Body) async throws -> StoredSession {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.query = query
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw ServerError.decoding("\(error)")
        }

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            throw ServerError.transport("\(error)")
        }
        guard (200..<300).contains(response.statusCode) else {
            throw ServerError.unauthorized("GoTrue \(path) failed with status \(response.statusCode)")
        }

        let payload: GoTrueSession
        do {
            payload = try JSONDecoder().decode(GoTrueSession.self, from: data)
        } catch {
            throw ServerError.decoding("\(error)")
        }
        return StoredSession(
            accessToken: payload.accessToken, refreshToken: payload.refreshToken,
            expiresAt: now().addingTimeInterval(payload.expiresIn), userId: payload.user.id
        )
    }

    private struct RefreshBody: Encodable {
        let refreshToken: String
        enum CodingKeys: String, CodingKey { case refreshToken = "refresh_token" }
    }

    private struct GoTrueSession: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Double
        let user: GoTrueUser
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case user
        }
    }

    private struct GoTrueUser: Decodable {
        let id: String
    }
}
