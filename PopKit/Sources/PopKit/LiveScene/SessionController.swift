import Foundation

/// The Orbis session's transport: bundled JS through `LiveSceneBridge` in the app,
/// a scripted fake in tests (docs/CONTRACTS.md §2 `LiveScene`).
public protocol SceneTransport: Sendable {
    /// Connects with a freshly minted Reactor token, returning the session id to report.
    func connect(jwt: String) async throws -> String
    func prepare(still: Data, prompt: String) async throws
    func start() async throws
    func disconnect() async
}

/// Time, abstracted so `SessionController`'s backoff waits can be faked in tests.
public protocol SessionClock: Sendable {
    func now() -> Date
    func sleep(for seconds: TimeInterval) async throws
}

public struct SystemClock: SessionClock {
    public init() {}

    public func now() -> Date { Date() }

    public func sleep(for seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }
}

/// Drives `SessionMachine` against the real `PopServer` (for minting) and
/// `SceneTransport` (for the Orbis connection), turning its effects into calls and
/// feeding the results back in as events (ROADMAP §2 `SessionController`).
public actor SessionController {
    private let machine: SessionMachine
    private let server: PopServer
    private let transport: SceneTransport
    private let clock: SessionClock

    public private(set) var state: SessionState = .initial
    private var pendingStill: Data?
    private var pendingPrompt: String?
    private var backoffTask: Task<Void, Never>?

    public init(server: PopServer, transport: SceneTransport, clock: SessionClock = SystemClock(), machine: SessionMachine = SessionMachine()) {
        self.server = server
        self.transport = transport
        self.clock = clock
        self.machine = machine
    }

    public func warmUp() async {
        await apply(.warmUpRequested)
    }

    public func animate(page: Int, still: Data, prompt: String) async {
        pendingStill = still
        pendingPrompt = prompt
        await apply(.animateRequested(page: page))
    }

    /// The transport reported the connection dropped while ready or animating.
    public func reportDisconnected(_ reason: String) async {
        await apply(.disconnected(reason))
    }

    /// Ends the session for good: cancels any pending reconnect, disconnects, and asks the
    /// server to end any of this user's sessions still open (R-30). A connect still in
    /// flight is disconnected as soon as it lands (`performConnect`).
    public func kill() async {
        backoffTask?.cancel()
        backoffTask = nil
        let wasConnecting = isConnecting
        await apply(.killRequested)
        if wasConnecting { await transport.disconnect() }
        _ = try? await server.reactorCleanup()
    }

    private var isConnecting: Bool {
        switch state.phase {
        case .connecting, .minting, .reconnecting: true
        default: false
        }
    }

    /// Dollars accumulated since the session first connected (Stable's rate), or 0
    /// if it never has or has since ended.
    public func credits(at now: Date? = nil) -> Double {
        CreditMeter.credits(for: state, at: now ?? clock.now())
    }

    // MARK: - driving effects

    private func apply(_ event: SessionEvent) async {
        let (newState, effect) = machine.reduce(state, event, now: clock.now())
        state = newState
        guard let effect else { return }
        await perform(effect)
    }

    private func perform(_ effect: SessionEffect) async {
        switch effect {
        case .mintToken:
            await performMint()
        case let .connect(jwt):
            await performConnect(jwt: jwt)
        case let .showPage(index):
            await performShowPage(index: index)
        case .disconnect:
            await transport.disconnect()
        case let .scheduleReconnect(after):
            scheduleReconnect(after: after)
        }
    }

    private func performMint() async {
        do {
            let response = try await server.reactorMint()
            await apply(.tokenMinted(jwt: response.jwt, expiresAt: Date(timeIntervalSince1970: response.expiresAt)))
        } catch let error as ServerError {
            await apply(.tokenMintFailed(error.message))
        } catch {
            await apply(.tokenMintFailed("\(error)"))
        }
    }

    private func performConnect(jwt: String) async {
        do {
            let sessionId = try await transport.connect(jwt: jwt)
            // Killed (or given up) while connecting: this connection must not stay open.
            guard state.phase != .killed, state.phase != .fallback else {
                await transport.disconnect()
                return
            }
            try? await server.reactorReport(sessionId: sessionId)
            await apply(.connected(sessionId: sessionId))
        } catch let error as ServerError {
            await apply(.connectFailed(error.message))
        } catch {
            await apply(.connectFailed("\(error)"))
        }
    }

    private func performShowPage(index: Int) async {
        guard let still = pendingStill, let prompt = pendingPrompt else { return }
        do {
            try await transport.prepare(still: still, prompt: prompt)
            try await transport.start()
        } catch {
            await apply(.stageFailed("\(error)"))
        }
    }

    private func scheduleReconnect(after seconds: TimeInterval) {
        backoffTask?.cancel()
        backoffTask = Task {
            do {
                try await self.clock.sleep(for: seconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self.apply(.reconnectTick(now: self.clock.now()))
        }
    }
}
