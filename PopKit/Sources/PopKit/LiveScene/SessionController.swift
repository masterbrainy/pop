import Foundation

/// The Orbis session's transport: bundled JS through `LiveSceneBridge` in the app,
/// a scripted fake in tests (docs/CONTRACTS.md §2 `LiveScene`).
public protocol SceneTransport: Sendable {
    /// Connects with a freshly minted Reactor token, returning the session id to report.
    func connect(jwt: String) async throws -> String
    /// Prepares page flow `generation`. A newer generation supersedes it: the transport then
    /// throws `SceneTransportError.superseded` instead of finishing.
    func prepare(still: Data, prompt: String, generation: Int) async throws
    func start(generation: Int) async throws
    func disconnect() async
}

public enum SceneTransportError: Error, Equatable {
    /// A newer page flow replaced this one on the same session. Not a failure.
    case superseded
}

/// How one `SessionController.animate` call ended.
public enum AnimateOutcome: Sendable, Equatable {
    /// Prepared and started; the first frame should follow.
    case started
    /// A newer page flow took over before this one started.
    case superseded
    /// Prepare or start failed; the session stays connected for the next page.
    case failed(String)
    /// No connected session to animate on (warming up, reconnecting, fallen back or killed).
    case notReady
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
    /// The newest page flow asked for; a reconnect re-shows it.
    private var pending: PendingPage?
    private var backoffTask: Task<Void, Never>?

    private struct PendingPage {
        let still: Data
        let prompt: String
        let generation: Int
    }

    public init(server: PopServer, transport: SceneTransport, clock: SessionClock = SystemClock(), machine: SessionMachine = SessionMachine()) {
        self.server = server
        self.transport = transport
        self.clock = clock
        self.machine = machine
    }

    public func warmUp() async {
        await apply(.warmUpRequested)
    }

    /// Prepares and starts `page` as page flow `generation` (newest wins). The actor is
    /// re-entered while a flow awaits the transport, so a turn or revision mid-prepare starts
    /// a newer flow; the older one then ends as `.superseded` without touching the session.
    public func animate(page: Int, still: Data, prompt: String, generation: Int) async -> AnimateOutcome {
        let request = PendingPage(still: still, prompt: prompt, generation: generation)
        pending = request
        guard case .showPage = transition(.animateRequested(page: page)) else { return .notReady }
        return await show(request)
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
        guard let effect = transition(event) else { return }
        await perform(effect)
    }

    /// Runs the machine and stores the new state; the caller performs the effect.
    private func transition(_ event: SessionEvent) -> SessionEffect? {
        let (newState, effect) = machine.reduce(state, event, now: clock.now())
        state = newState
        return effect
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

    /// A reconnect re-shows the newest page flow; nobody waits on its outcome.
    private func performShowPage(index: Int) async {
        guard let pending else { return }
        _ = await show(pending)
    }

    private func show(_ page: PendingPage) async -> AnimateOutcome {
        do {
            try await transport.prepare(still: page.still, prompt: page.prompt, generation: page.generation)
            guard isNewest(page) else { return .superseded }
            try await transport.start(generation: page.generation)
            return isNewest(page) ? .started : .superseded
        } catch {
            // A newer flow owns the session now; this one's failure says nothing about it.
            if error as? SceneTransportError == .superseded || !isNewest(page) { return .superseded }
            let message = (error as? ServerError)?.message ?? "\(error)"
            await apply(.stageFailed(message))
            return .failed(message)
        }
    }

    private func isNewest(_ page: PendingPage) -> Bool {
        pending?.generation == page.generation
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
