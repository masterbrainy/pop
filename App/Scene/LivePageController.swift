import Foundation
import Observation
import PopKit

/// Brings the page on screen to life with Orbis (ROADMAP Phase 3): warm up on a new book,
/// run reset → set_image → set_prompt → start for each page shown, crossfade from the still
/// to video on the first frame, record the page's clip, and fall back to the slow pan if
/// Orbis is off or fails. `SessionController` owns the lifecycle and reconnects.
@MainActor
@Observable
final class LivePageController {
    enum Status: Equatable {
        case off
        case warming
        case preparing(page: Int)
        case live(page: Int)
        case fallback(String)
    }

    /// How long each page's clip runs; saved books loop it (G0/D4).
    static let clipSeconds = 10

    private(set) var status: Status = .off
    private(set) var credits: Double = 0
    let bridge = LiveSceneBridge()

    /// Called with (page id, clip file) when a page's clip is recorded.
    @ObservationIgnored var onClip: @MainActor (UUID, URL) -> Void = { _, _ in }
    @ObservationIgnored private var session: SessionController?
    @ObservationIgnored private var eventsTask: Task<Void, Never>?
    @ObservationIgnored private var clipTask: Task<Void, Never>?
    @ObservationIgnored private var currentPage: PageContent?
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    /// Whether a session is up (or coming up) to animate pages.
    var canAnimate: Bool {
        switch status {
        case .off, .fallback: false
        default: true
        }
    }

    var isLive: Bool {
        if case .live = status { return true }
        return false
    }

    /// Loads the page and connects, so the first page animates quickly (ROADMAP §9 warm-up).
    func warmUp(server: any PopServer) async {
        guard session == nil else { return }
        status = .warming
        let session = SessionController(server: server, transport: BridgeTransport(bridge: bridge))
        self.session = session
        listen()
        watchSession()
        do {
            try await bridge.load()
            await session.warmUp()
        } catch {
            status = .fallback("The living page couldn't start: \(error.localizedDescription)")
        }
    }

    /// Animates `page` if it has a still and a motion prompt; otherwise keeps the still.
    func show(_ page: PageContent, still: Data, prompt: String) async {
        guard let session else { return }
        if currentPage?.id == page.id, currentPage?.version == page.version, isLive || status == .preparing(page: page.index) { return }
        await stopClip()
        currentPage = page
        status = .preparing(page: page.index)
        await session.animate(page: page.index, still: still, prompt: prompt)
    }

    /// The page turned away before its clip was done: drop the partial clip.
    func pageWillChange() async {
        await stopClip()
        currentPage = nil
        if case .live = status { status = .warming }
    }

    func kill() async {
        clipTask?.cancel()
        eventsTask?.cancel()
        pollTask?.cancel()
        await bridge.cancelClip()
        await session?.kill()
        session = nil
        status = .off
    }

    private func stopClip() async {
        clipTask?.cancel()
        clipTask = nil
        await bridge.cancelClip()
    }

    private func listen() {
        eventsTask?.cancel()
        eventsTask = Task { [weak self] in
            guard let events = self?.bridge.events else { return }
            for await event in events {
                guard let self else { return }
                await self.handle(event)
            }
        }
    }

    private func handle(_ event: SceneEvent) async {
        switch event {
        case .firstFrame:
            guard let page = currentPage else { return }
            status = .live(page: page.index)
            recordClip(for: page)
        case let .error(code, message, recoverable):
            AppLog.scene.error("live scene error \(code, privacy: .public): \(message, privacy: .public)")
            if recoverable { await session?.reportDisconnected(message) }
        case let .status(value) where value == "disconnected":
            if currentPage != nil { await session?.reportDisconnected("disconnected") }
        default:
            break
        }
    }

    private func recordClip(for page: PageContent) {
        clipTask?.cancel()
        clipTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await bridge.startClip(maxSeconds: Self.clipSeconds)
                try await Task.sleep(for: .seconds(Self.clipSeconds))
                let clip = try await bridge.stopClip()
                guard currentPage?.id == page.id, currentPage?.version == page.version else { return }
                onClip(page.id, clip.url)
            } catch is CancellationError {
                return
            } catch {
                AppLog.scene.error("clip failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Mirrors the session's phase into `status` and the credit meter.
    private func watchSession() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let session = self.session else { return }
                let state = await session.state
                self.credits = await session.credits()
                switch state.phase {
                case .fallback:
                    self.status = .fallback("Live pictures are resting; the still pictures carry on.")
                case let .failed(message):
                    self.status = .fallback(message)
                case .ready where self.status == .warming || self.status == .off:
                    self.status = .warming
                default:
                    break
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

/// `SceneTransport` over the web bridge, for `SessionController`.
struct BridgeTransport: SceneTransport {
    let bridge: LiveSceneBridge

    func connect(jwt: String) async throws -> String {
        let result = try await bridge.connect(jwt: jwt)
        return result.sessionId ?? ""
    }

    func prepare(still: Data, prompt: String) async throws {
        let mime = still.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? "image/png" : "image/jpeg"
        _ = try await bridge.prepare(still: still, mimeType: mime, prompt: prompt)
    }

    func start() async throws {
        _ = try await bridge.start()
    }

    func disconnect() async {
        try? await bridge.disconnect()
    }
}
