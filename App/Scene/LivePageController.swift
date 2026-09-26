import Foundation
import Observation
import PopKit

/// Brings the page on screen to life with Orbis (ROADMAP Phase 3): warm up on a new book,
/// run reset → set_image → set_prompt → start for each page shown, crossfade from the still
/// to video on the first frame, record the page's clip, and fall back to the slow pan if
/// Orbis is off or fails. `SessionController` owns the lifecycle and reconnects. While a page
/// is live, sampled frames go through moderation (`FrameTripwire`); a flagged frame sends the
/// page back to its still for good.
@MainActor
@Observable
final class LivePageController {
    enum Status: Equatable {
        case off
        case warming
        case preparing(page: Int)
        case live(page: Int)
        /// A frame on this page was flagged, so the page keeps its still.
        case held(page: Int)
        case fallback(String)
    }

    /// How long each page's clip runs; saved books loop it (G0/D4).
    static let clipSeconds = 10

    private(set) var status: Status = .off
    private(set) var credits: Double = 0
    private(set) var framesChecked = 0
    private(set) var framesFlagged = 0
    let bridge = LiveSceneBridge()

    /// Called with (page id, clip file) when a page's clip is recorded.
    @ObservationIgnored var onClip: @MainActor (UUID, URL) -> Void = { _, _ in }
    /// Called with the page id when a sampled frame on that page is flagged.
    @ObservationIgnored var onFrameFlagged: @MainActor (UUID) -> Void = { _ in }
    @ObservationIgnored private var tripwire: FrameTripwire?
    @ObservationIgnored private var tripwireTask: Task<Void, Never>?
    /// Page versions ("id#version") that stay on their still after a flagged frame.
    @ObservationIgnored private var heldPages: Set<String> = []
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
        tripwire = FrameTripwire(server: server)
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
        guard !isHeld(page) else {
            await stopClip()
            currentPage = page
            status = .held(page: page.index)
            return
        }
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

    /// Whether a flagged frame keeps this version of `page` on its still.
    func isHeld(_ page: PageContent) -> Bool {
        heldPages.contains(Self.key(page))
    }

    func kill() async {
        tripwireTask?.cancel()
        clipTask?.cancel()
        eventsTask?.cancel()
        pollTask?.cancel()
        await bridge.cancelClip()
        await session?.kill()
        session = nil
        status = .off
    }

    private func stopClip() async {
        tripwireTask?.cancel()
        tripwireTask = nil
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
            watchFrames(on: page)
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

    private func watchFrames(on page: PageContent) {
        tripwireTask?.cancel()
        guard let tripwire else { return }
        tripwireTask = Task { [weak self] in
            var index = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: FrameTripwire.delay(beforeCheck: index))
                index += 1
                guard let self, !Task.isCancelled, self.currentPage?.id == page.id, self.isLive else { return }
                guard let frame = try? await self.bridge.sampleFrame(maxSide: FrameTripwire.maxSide) else { continue }
                let verdict = await tripwire.check(base64: frame.base64, mimeType: frame.mimeType)
                self.framesChecked += 1
                switch verdict {
                case .clear:
                    break
                case let .unchecked(reason):
                    AppLog.scene.error("frame check failed: \(reason, privacy: .public)")
                case let .flagged(categories):
                    AppLog.scene.error("frame flagged on page \(page.index): \(categories.joined(separator: ","), privacy: .public)")
                    await self.hold(page)
                    return
                }
            }
        }
    }

    /// A flagged frame: stop the video, drop the clip, and keep the page's still.
    private func hold(_ page: PageContent) async {
        framesFlagged += 1
        heldPages.insert(Self.key(page))
        clipTask?.cancel()
        clipTask = nil
        await bridge.cancelClip()
        try? await bridge.pause()
        guard currentPage?.id == page.id else { return }
        status = .held(page: page.index)
        onFrameFlagged(page.id)
    }

    private static func key(_ page: PageContent) -> String { "\(page.id.uuidString)#\(page.version)" }

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
