import Foundation

/// The Orbis session lifecycle (ROADMAP §2 Phase 3): mint a token, connect, animate
/// pages, reconnect with backoff if the connection drops, and fall back to the
/// still image if reconnecting keeps failing.
public enum SessionPhase: Sendable, Equatable {
    case idle
    case minting
    case connecting
    case ready
    case animating(page: Int)
    case reconnecting(attempt: Int, backoff: TimeInterval)
    /// Gave up reconnecting: show the still image instead of live video.
    case fallback
    case failed(String)
    case killed
}

public struct SessionState: Sendable, Equatable {
    public let phase: SessionPhase
    public let jwt: String?
    public let jwtExpiresAt: Date?
    /// The page last requested to animate, kept so a successful reconnect can resume it.
    public let currentPage: Int?
    public let sessionId: String?
    /// Set on the first successful connect, cleared on kill or fallback — the
    /// credit meter's window.
    public let connectedSince: Date?

    public init(
        phase: SessionPhase = .idle, jwt: String? = nil, jwtExpiresAt: Date? = nil,
        currentPage: Int? = nil, sessionId: String? = nil, connectedSince: Date? = nil
    ) {
        self.phase = phase
        self.jwt = jwt
        self.jwtExpiresAt = jwtExpiresAt
        self.currentPage = currentPage
        self.sessionId = sessionId
        self.connectedSince = connectedSince
    }

    public static let initial = SessionState()
}

public enum SessionEvent: Sendable, Equatable {
    case warmUpRequested
    case tokenMinted(jwt: String, expiresAt: Date)
    case tokenMintFailed(String)
    case connected(sessionId: String)
    case connectFailed(String)
    case animateRequested(page: Int)
    /// The transport reported the connection dropped while ready or animating.
    case disconnected(String)
    /// `prepare` or `start` failed while connected; the session stays open and ready.
    case stageFailed(String)
    /// The backoff timer fired; try again.
    case reconnectTick(now: Date)
    case killRequested
}

/// What the driver (`SessionController`) should do after a transition. Every
/// transition produces at most one.
public enum SessionEffect: Sendable, Equatable {
    case mintToken
    case connect(jwt: String)
    /// `prepare(still:prompt:)` then `start()` for this page.
    case showPage(index: Int)
    case disconnect
    case scheduleReconnect(after: TimeInterval)
}

/// Pure reducer: `(state, event) -> (state, effect?)`. No I/O, no clock reads beyond
/// the `now` passed in, so it's directly testable without a fake transport.
public struct SessionMachine: Sendable {
    public let maxAttempts: Int
    public let initialBackoff: TimeInterval
    public let backoffCap: TimeInterval

    public init(maxAttempts: Int = 5, initialBackoff: TimeInterval = 1, backoffCap: TimeInterval = 30) {
        self.maxAttempts = maxAttempts
        self.initialBackoff = initialBackoff
        self.backoffCap = backoffCap
    }

    public func reduce(_ state: SessionState, _ event: SessionEvent, now: Date) -> (SessionState, SessionEffect?) {
        switch (state.phase, event) {
        case (.idle, .warmUpRequested):
            return (SessionState(phase: .minting), .mintToken)

        case let (.minting, .tokenMinted(jwt, expiresAt)):
            let updated = SessionState(phase: .connecting, jwt: jwt, jwtExpiresAt: expiresAt)
            return (updated, .connect(jwt: jwt))

        case let (.minting, .tokenMintFailed(message)):
            return (SessionState(phase: .failed(message)), nil)

        case let (.connecting, .connected(sessionId)):
            let updated = SessionState(
                phase: .ready, jwt: state.jwt, jwtExpiresAt: state.jwtExpiresAt,
                sessionId: sessionId, connectedSince: state.connectedSince ?? now
            )
            return (updated, nil)

        case let (.connecting, .connectFailed(message)):
            return (SessionState(phase: .failed(message), jwt: state.jwt, jwtExpiresAt: state.jwtExpiresAt), nil)

        case (.ready, .animateRequested(let page)), (.animating, .animateRequested(let page)):
            let updated = SessionState(
                phase: .animating(page: page), jwt: state.jwt, jwtExpiresAt: state.jwtExpiresAt,
                currentPage: page, sessionId: state.sessionId, connectedSince: state.connectedSince
            )
            return (updated, .showPage(index: page))

        case (.ready, .disconnected), (.animating, .disconnected):
            return attemptFailed(state, failedAttempt: 0)

        // A page that failed to prepare or start is not a dropped connection. The session is
        // still open (and its `connect` refuses a second connection), so reconnecting could
        // only walk the ladder into fallback for the whole book. Stay ready for the next page.
        case (.ready, .stageFailed), (.animating, .stageFailed):
            let updated = SessionState(
                phase: .ready, jwt: state.jwt, jwtExpiresAt: state.jwtExpiresAt,
                sessionId: state.sessionId, connectedSince: state.connectedSince
            )
            return (updated, nil)

        case let (.reconnecting, .reconnectTick(tickNow)):
            if let jwt = state.jwt, let expiresAt = state.jwtExpiresAt, tickNow < expiresAt {
                return (state, .connect(jwt: jwt))
            }
            return (state, .mintToken)

        case let (.reconnecting, .tokenMinted(jwt, expiresAt)):
            let updated = SessionState(
                phase: state.phase, jwt: jwt, jwtExpiresAt: expiresAt,
                currentPage: state.currentPage, sessionId: state.sessionId, connectedSince: state.connectedSince
            )
            return (updated, .connect(jwt: jwt))

        case let (.reconnecting(attempt, _), .tokenMintFailed):
            return attemptFailed(state, failedAttempt: attempt)

        case let (.reconnecting(attempt, _), .connectFailed):
            return attemptFailed(state, failedAttempt: attempt)

        case let (.reconnecting, .connected(sessionId)):
            let connectedSince = state.connectedSince ?? now
            if let page = state.currentPage {
                let updated = SessionState(
                    phase: .animating(page: page), jwt: state.jwt, jwtExpiresAt: state.jwtExpiresAt,
                    currentPage: page, sessionId: sessionId, connectedSince: connectedSince
                )
                return (updated, .showPage(index: page))
            }
            let updated = SessionState(phase: .ready, jwt: state.jwt, jwtExpiresAt: state.jwtExpiresAt, sessionId: sessionId, connectedSince: connectedSince)
            return (updated, nil)

        case (_, .killRequested):
            guard state.phase != .killed else { return (state, nil) }
            let effect: SessionEffect? = isConnectedPhase(state.phase) ? .disconnect : nil
            let updated = SessionState(phase: .killed, jwt: state.jwt, jwtExpiresAt: state.jwtExpiresAt, currentPage: state.currentPage, sessionId: state.sessionId, connectedSince: nil)
            return (updated, effect)

        default:
            return (state, nil)
        }
    }

    /// One reconnect attempt just failed. Schedules the next one with doubled
    /// backoff, or gives up and falls back after `maxAttempts`.
    private func attemptFailed(_ state: SessionState, failedAttempt: Int) -> (SessionState, SessionEffect?) {
        let nextAttempt = failedAttempt + 1
        guard nextAttempt <= maxAttempts else {
            let updated = SessionState(phase: .fallback, jwt: state.jwt, jwtExpiresAt: state.jwtExpiresAt, currentPage: state.currentPage, sessionId: state.sessionId, connectedSince: nil)
            return (updated, .disconnect)
        }
        let backoff = min(initialBackoff * pow(2, Double(nextAttempt - 1)), backoffCap)
        let updated = SessionState(
            phase: .reconnecting(attempt: nextAttempt, backoff: backoff), jwt: state.jwt, jwtExpiresAt: state.jwtExpiresAt,
            currentPage: state.currentPage, sessionId: state.sessionId, connectedSince: state.connectedSince
        )
        return (updated, .scheduleReconnect(after: backoff))
    }

    private func isConnectedPhase(_ phase: SessionPhase) -> Bool {
        switch phase {
        case .ready, .animating, .reconnecting: true
        default: false
        }
    }
}

/// Stable's per-minute rate, accumulated only while `SessionState.connectedSince` is set.
public enum CreditMeter {
    public static let ratePerMinute = 0.582

    public static func credits(for state: SessionState, at now: Date) -> Double {
        guard let since = state.connectedSince else { return 0 }
        let minutes = max(0, now.timeIntervalSince(since)) / 60
        return minutes * ratePerMinute
    }
}
