import Foundation
import Observation
import PopKit

/// Brings the page on screen to life with Orbis (ROADMAP Phase 3): warm up on a new book,
/// run reset → set_image → set_prompt → start for each page shown, crossfade from the still
/// to video on the first frame, record the page's clip, and fall back to the slow pan if
/// Orbis is off or fails. `SessionController` owns the lifecycle and reconnects. While a page
/// is live, sampled frames go through moderation (`FrameTripwire`); a flagged frame sends the
/// page back to its still for good.
///
/// Each show is a numbered page flow (`LiveShowTracker`): a turn or revision mid-prepare
/// supersedes the older flow, only the newest flow's first frame makes a page live, and a
/// flow with no first frame within `firstFrameWatchdog` is retried once, then the page keeps
/// its still until it's shown again.
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
    static let clipSeconds = FrameTripwire.clipSeconds
    /// `generation_started` → first frame measured 4.8 s (ROADMAP 0.3a); twice that is a stall.
    static let firstFrameWatchdog: Duration = .seconds(10)

    private(set) var status: Status = .off
    private(set) var credits: Double = 0
    private(set) var framesChecked = 0
    private(set) var framesFlagged = 0
    /// Page shown → first live frame, in ms, for every page so far (R-36).
    private(set) var firstFrameMs: [Int] = []
    /// The page version ("id#version") the live video belongs to, so a view never shows one
    /// page's video over another page's still.
    private(set) var liveKey: String?
    let bridge = LiveSceneBridge()

    /// Called with (page id, clip file) when a page's clip is recorded.
    @ObservationIgnored var onClip: @MainActor (UUID, URL) -> Void = { _, _ in }
    /// Called with the page id when a sampled frame on that page is flagged.
    @ObservationIgnored var onFrameFlagged: @MainActor (UUID) -> Void = { _ in }
    /// Called with (page index, ms from show to its first live frame).
    @ObservationIgnored var onFirstFrame: @MainActor (Int, Int) -> Void = { _, _ in }
    @ObservationIgnored private var shownAt: ContinuousClock.Instant?
    @ObservationIgnored private var tripwire: FrameTripwire?
    @ObservationIgnored private var tripwireTask: Task<Void, Never>?
    /// Page versions ("id#version") that stay on their still after a flagged frame.
    @ObservationIgnored private var heldPages: Set<String> = []
    @ObservationIgnored private var session: SessionController?
    @ObservationIgnored private var eventsTask: Task<Void, Never>?
    @ObservationIgnored private var clipTask: Task<Void, Never>?
    @ObservationIgnored private var currentPage: PageContent?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var watchdogTask: Task<Void, Never>?
    @ObservationIgnored private var tracker = LiveShowTracker()

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

    /// Whether the live video on screen is this version of `page`.
    func isShowingLive(_ page: PageContent?) -> Bool {
        guard isLive, let page else { return false }
        return liveKey == Self.key(page)
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
    ///
    /// StoryMaker calls this and `pageWillChange` from separate Tasks, so every state change
    /// happens before the first `await`; a suspended call can't then undo a newer one.
    func show(_ page: PageContent, still: Data, prompt: String) async {
        guard session != nil else { return }
        guard !isHeld(page) else {
            leaveCurrentPage()
            currentPage = page
            status = .held(page: page.index)
            await stopClip()
            return
        }
        if currentPage.map(Self.key) == Self.key(page), isLive || status == .preparing(page: page.index) { return }
        leaveCurrentPage()
        currentPage = page
        shownAt = .now
        let generation = tracker.begin(key: Self.key(page))
        status = .preparing(page: page.index)
        await stopClip()
        guard tracker.isCurrent(generation) else { return }
        await run(generation, page: page, still: still, prompt: prompt)
    }

    /// The page turned away before its clip was done: drop the partial clip, and make sure
    /// nothing still running for it (a late first frame, a watchdog) can touch the next page.
    func pageWillChange() async {
        leaveCurrentPage()
        currentPage = nil
        await stopClip()
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
        watchdogTask?.cancel()
        tracker.leave()
        liveKey = nil
        await bridge.cancelClip()
        await session?.kill()
        session = nil
        status = .off
    }

    // MARK: - page flows

    /// Prepares and starts one page flow and handles how it ended.
    private func run(_ generation: Int, page: PageContent, still: Data, prompt: String) async {
        guard let session else { return }
        status = .preparing(page: page.index)
        let outcome = await session.animate(page: page.index, still: still, prompt: prompt, generation: generation)
        guard tracker.isCurrent(generation) else { return }
        switch outcome {
        case .started:
            armWatchdog(generation, page: page, still: still, prompt: prompt)
        case .superseded:
            break
        case .notReady:
            // Not connected yet: step back so the next show of this page (after warm-up) runs.
            if status == .preparing(page: page.index) { status = .warming }
        case let .failed(reason):
            await recover(generation, page: page, still: still, prompt: prompt, reason: reason)
        }
    }

    /// No first frame arrived in time: the page mustn't sit in `.preparing` forever.
    private func armWatchdog(_ generation: Int, page: PageContent, still: Data, prompt: String) {
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            try? await Task.sleep(for: Self.firstFrameWatchdog)
            guard !Task.isCancelled, let self, self.tracker.isCurrent(generation), !self.isLive else { return }
            await self.recover(generation, page: page, still: still, prompt: prompt, reason: "no first frame within \(Self.firstFrameWatchdog)")
        }
    }

    private func recover(_ generation: Int, page: PageContent, still: Data, prompt: String, reason: String) async {
        switch tracker.stalled(generation: generation) {
        case .ignore:
            return
        case let .retry(next):
            AppLog.scene.error("page \(page.index + 1) did not come alive (\(reason, privacy: .public)); retrying once")
            await run(next, page: page, still: still, prompt: prompt)
        case .giveUp:
            AppLog.scene.error("page \(page.index + 1) did not come alive (\(reason, privacy: .public)); keeping its still")
            if status == .preparing(page: page.index) { status = .warming }
        }
    }

    /// Synchronous on purpose (see `show`); the caller stops the clip afterwards.
    private func leaveCurrentPage() {
        watchdogTask?.cancel()
        watchdogTask = nil
        tracker.leave()
        liveKey = nil
        switch status {
        case .live, .preparing, .held: status = .warming
        default: break
        }
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
        case let .firstFrame(generation, _, _, _):
            // Only the newest flow's first frame counts; a late one from a page already left is dropped.
            guard let page = currentPage, tracker.firstFrame(generation: generation) else { return }
            watchdogTask?.cancel()
            watchdogTask = nil
            liveKey = Self.key(page)
            status = .live(page: page.index)
            if let shownAt {
                let ms = Int((ContinuousClock.now - shownAt) / .milliseconds(1))
                self.shownAt = nil
                firstFrameMs.append(ms)
                onFirstFrame(page.index, ms)
            }
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
                settleOnClip(page)
            } catch is CancellationError {
                return
            } catch {
                AppLog.scene.error("clip failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// The page's clip is recorded: it loops from now on (`ArtPageView`), so hide the live
    /// video. Orbis drifts further from the still the longer it runs (characters change shape
    /// and colour, the style turns photoreal); the first seconds are the ones worth keeping.
    private func settleOnClip(_ page: PageContent) {
        guard liveKey == Self.key(page) else { return }
        tripwireTask?.cancel()
        tripwireTask = nil
        leaveCurrentPage()
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
        liveKey = nil
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

    /// Sends Orbis a ~832×480 JPEG rather than the stored 1344×768 PNG (about a tenth of the
    /// bytes, so a shorter upload in every prepare). Runs on the session's actor, off the main thread.
    func prepare(still: Data, prompt: String, generation: Int) async throws {
        let upload = OrbisStill.jpeg(from: still) ?? still
        let mime = upload.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? "image/png" : "image/jpeg"
        try await superseding {
            _ = try await bridge.prepare(still: upload, mimeType: mime, prompt: prompt, generation: generation)
        }
    }

    func start(generation: Int) async throws {
        try await superseding {
            _ = try await bridge.start(generation: generation)
        }
    }

    func disconnect() async {
        try? await bridge.disconnect()
    }

    /// The page's "superseded: …" rejection becomes `SceneTransportError.superseded`.
    private func superseding(_ body: () async throws -> Void) async throws {
        do {
            try await body()
        } catch let error as LiveSceneBridge.BridgeError where error.isSuperseded {
            throw SceneTransportError.superseded
        }
    }
}
