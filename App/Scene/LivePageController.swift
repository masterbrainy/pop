import Foundation
import Observation
import PopKit

/// Brings pages to life with ONE Orbis session (ROADMAP Phase 3): record, then loop, then
/// pre-animate the page behind (`PreRollPlanner`).
///
/// The page on screen animates live and its first 10 s are recorded; the clip is moderated,
/// baked into a seamless loop and attached, and the page crossfades from the live video to
/// its loop. The session, now free, pre-animates the page behind while hidden and records its
/// loop too. At the fold that page is either still running (its video is revealed) or already
/// has its loop (it plays, and the page after it is pre-animated next).
///
/// `SessionController` owns the connection and reconnects. Each flow is numbered
/// (`LiveShowTracker`): only the newest flow's first frame counts, and a flow with no first
/// frame within `firstFrameWatchdog` is retried once, then its page is spent (it keeps its
/// still until it's shown again). While a page shows live, sampled frames go through
/// moderation (`FrameTripwire`); a flagged frame holds the page on its still for good.
@MainActor
@Observable
final class LivePageController {
    enum Status: Equatable {
        case off
        case warming
        case preparing(page: Int)
        case live(page: Int)
        /// The page on screen plays its baked loop.
        case looping(page: Int)
        /// A frame on this page was flagged, so the page keeps its still.
        case held(page: Int)
        case fallback(String)
    }

    /// A page with the motion prompt it animates with (nil until one is made).
    struct LivePage: Equatable {
        let page: PageContent
        let prompt: String?
        var key: PageKey { page.key }
    }

    /// The page flow the session is running now.
    struct Flow: Equatable {
        let key: PageKey
        let index: Int
        var generation: Int
        var isHidden: Bool
        var hasFirstFrame: Bool

        var slot: PreRollPlanner.Slot { .init(key: key, isHidden: isHidden, hasFirstFrame: hasFirstFrame) }
    }

    enum SessionStatus: Equatable {
        case off
        case warming
        case fallback(String)
    }

    /// How long each page's clip runs; the baked loop is a little shorter.
    static let clipSeconds = FrameTripwire.clipSeconds
    /// `generation_started` → first frame measured 4.8 s (ROADMAP 0.3a); twice that is a stall.
    static let firstFrameWatchdog: Duration = .seconds(10)
    /// A loop that never reports it's ready still takes over after this long.
    static let handOverTimeout: Duration = .seconds(2)

    private(set) var sessionStatus: SessionStatus = .off
    private(set) var credits: Double = 0
    var framesChecked = 0
    var framesFlagged = 0
    /// Page shown → first live frame, in ms, for pages animated in view (R-36).
    private(set) var firstFrameMs: [Int] = []
    private(set) var metrics = PreRollMetrics()
    private(set) var display: PreRollPlanner.Display = .still
    /// The page version whose live video is on screen, so a view never shows one page's
    /// video over another page's still. Only ever the page on screen.
    private(set) var liveKey: PageKey?
    private(set) var onScreen: LivePage?
    private(set) var behind: LivePage?
    var flow: Flow?
    /// Page versions a flagged frame (or clip) keeps on their still.
    var held: Set<PageKey> = []
    /// Page versions whose flow ran without giving a loop; animated again only when next shown.
    var spent: Set<PageKey> = []

    let bridge = LiveSceneBridge()
    let dock: LiveSceneDock

    /// Called with (page version, loop file) once a page's clip is checked and baked.
    @ObservationIgnored var onClip: @MainActor (PageKey, URL) -> Void = { _, _ in }
    /// Called with the page version when a frame or clip of it is flagged.
    @ObservationIgnored var onFrameFlagged: @MainActor (PageKey) -> Void = { _ in }
    /// Called with (page index, ms from show to its first live frame).
    @ObservationIgnored var onFirstFrame: @MainActor (Int, Int) -> Void = { _, _ in }
    /// A line for the scripted run's log (story.log).
    @ObservationIgnored var onLog: @MainActor (String) -> Void = { _ in }

    @ObservationIgnored var session: SessionController?
    @ObservationIgnored var tripwire: FrameTripwire?
    @ObservationIgnored var tracker = LiveShowTracker()
    @ObservationIgnored var tripwireTask: Task<Void, Never>?
    @ObservationIgnored var recordTask: Task<Void, Never>?
    @ObservationIgnored var processTasks: [PageKey: Task<Void, Never>] = [:]
    @ObservationIgnored private var eventsTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var watchdogTask: Task<Void, Never>?
    @ObservationIgnored private var sessionReady = false
    @ObservationIgnored private var revealing: Int?
    /// Loops that can show their first frame (`ClipPlayerView` said so), for the hand-over.
    @ObservationIgnored private var readyClips: Set<PageKey> = []
    @ObservationIgnored private var handOvers: Set<PageKey> = []
    /// Finishing the book: this page is recorded hidden, whatever is on screen.
    @ObservationIgnored private var completing: LivePage?
    @ObservationIgnored private var shownAt: ContinuousClock.Instant?
    /// The fold being timed to the first moving frame of the page it opened.
    @ObservationIgnored private var fold: (key: PageKey, at: ContinuousClock.Instant)?
    @ObservationIgnored private var crossfadeUntil: ContinuousClock.Instant?
    /// The recording in progress (by flow generation) and whether the live tripwire has
    /// watched its page the whole time; if not, its clip must pass its own frame checks.
    @ObservationIgnored var recordingWatch: (generation: Int, watched: Bool)?
    /// Pages that already recorded a second time after a loop failed.
    @ObservationIgnored var loopRetried: Set<PageKey> = []
    @ObservationIgnored private var server: (any PopServer)?
    @ObservationIgnored private var isRetryingWarmUp = false

    init() {
        dock = LiveSceneDock(webView: bridge.webView)
    }

    /// Whether a session is up (or coming up) to animate pages.
    var canAnimate: Bool {
        switch sessionStatus {
        case .off, .fallback: false
        case .warming: true
        }
    }

    var isLive: Bool { display == .live }

    var status: Status {
        switch sessionStatus {
        case .off: return .off
        case let .fallback(message): return .fallback(message)
        case .warming: break
        }
        guard let onScreen else { return .warming }
        let index = onScreen.page.index
        if held.contains(onScreen.key) { return .held(page: index) }
        switch display {
        case .live: return .live(page: index)
        case .clip: return .looping(page: index)
        case .still: return flow?.key == onScreen.key ? .preparing(page: index) : .warming
        }
    }

    /// One line on the page behind, for the debug overlay.
    var preRollText: String {
        guard let behind else { return "behind: none" }
        let page = "behind p\(behind.page.index + 1)"
        if behind.page.clipPath != nil { return "\(page): loop ready" }
        if held.contains(behind.key) { return "\(page): held" }
        if spent.contains(behind.key) { return "\(page): spent" }
        guard let flow, flow.key == behind.key else { return behind.prompt == nil ? "\(page): waiting" : "\(page): queued" }
        return "\(page): \(flow.hasFirstFrame ? "recording hidden" : "preparing hidden")"
    }

    /// Whether the live video on screen is this version of `page`.
    func isShowingLive(_ page: PageContent?) -> Bool {
        guard let page, let liveKey else { return false }
        return liveKey == page.key
    }

    /// Whether a flagged frame keeps this version of `page` on its still.
    func isHeld(_ page: PageContent) -> Bool {
        held.contains(page.key)
    }

    /// Whether this version of `page` already had its try and won't animate until shown again.
    func isSpent(_ page: PageContent) -> Bool {
        spent.contains(page.key)
    }

    /// Loads the page and connects, so the first page animates quickly (ROADMAP §9 warm-up).
    func warmUp(server: any PopServer) async {
        guard session == nil else { return }
        self.server = server
        sessionStatus = .warming
        let session = SessionController(server: server, transport: BridgeTransport(bridge: bridge))
        self.session = session
        tripwire = FrameTripwire(server: server)
        listen()
        watchSession()
        do {
            try await bridge.load()
            await session.warmUp()
            noteSessionPhase(await session.state.phase)
        } catch {
            sessionStatus = .fallback("The living page couldn't start: \(error.localizedDescription)")
        }
    }

    /// The page on screen and the page behind it (the one the next fold opens), with their
    /// motion prompts. StoryMaker calls this whenever either changes.
    func update(current: LivePage?, behind: LivePage?) {
        let previous = onScreen
        onScreen = current
        self.behind = behind
        if let current, current.key != previous?.key {
            shown(current, after: previous)
            retryWarmUpIfResting()
        }
        if let clip = StillImageLoader.url(for: behind?.page.clipPath) { ClipPreloader.shared.warm(clip) }
        armHandOverTimeout()
        replan()
    }

    /// Finishing the book: record `page` (hidden) whatever is on screen; nil to stop.
    func complete(_ page: LivePage?) {
        completing = page
        if let page { spent.remove(page.key) }
        replan()
    }

    /// `ClipPlayerView` can show this loop's first frame.
    func clipBecameReady(_ key: PageKey) {
        // A fold to a page whose loop was ready moves when its player shows the first frame.
        if key == onScreen?.key, liveKey != key { noteMotion(for: key) }
        guard !readyClips.contains(key) else { return }
        readyClips.insert(key)
        replan()
    }

    func kill() async {
        // The event reader stays: cancelling it would end the bridge's event stream for good,
        // and a later warm-up (back from the background) would never hear a first frame.
        tripwireTask?.cancel()
        pollTask?.cancel()
        endFlow()
        flow = nil
        sessionReady = false
        applyDisplay(.still)
        await bridge.cancelClip()
        await session?.kill()
        session = nil
        sessionStatus = .off
        // Pages with a loop keep playing it; nothing else moves until the session is back.
        replan()
    }

    // MARK: - planning

    /// Asks the planner what the session should do and what the page shows, then does it.
    /// Every state change happens before the first await, so an older call can't undo a newer one.
    func replan() {
        let plan = currentPlan()
        applyDisplay(plan.display)
        guard sessionReady, session != nil, canAnimate else { return }
        // The live video is crossfading to its loop: the session moves on once it's done.
        if let until = crossfadeUntil, ContinuousClock.now < until { return }
        crossfadeUntil = nil
        for action in plan.actions { perform(action) }
    }

    /// The live page on screen just handed over to its loop: keep its video running through
    /// the crossfade, then replan (which pre-animates the page behind).
    private func holdForCrossfade() {
        let pause = Duration.seconds(ArtPageView.handOverDuration) + .milliseconds(100)
        crossfadeUntil = .now.advanced(by: pause)
        Task { [weak self] in
            try? await Task.sleep(for: pause)
            self?.replan()
        }
    }

    private func currentPlan() -> PreRollPlanner.Plan {
        let screen = plannerPage(onScreen, isOnScreen: true)
        guard let completing, completing.key != onScreen?.key else {
            return PreRollPlanner.plan(onScreen: screen, behind: completing == nil ? plannerPage(behind, isOnScreen: false) : nil, slot: flow?.slot)
        }
        // Finishing: the page on screen steps aside so the page being completed gets the session.
        let deferred = screen.map { PreRollPlanner.Page(key: $0.key, canAnimate: $0.canAnimate, hasClip: $0.hasClip, isHeld: $0.isHeld, isSpent: true) }
        return PreRollPlanner.plan(onScreen: deferred, behind: plannerPage(completing, isOnScreen: false), slot: flow?.slot)
    }

    private func plannerPage(_ live: LivePage?, isOnScreen: Bool) -> PreRollPlanner.Page? {
        guard let live else { return nil }
        let key = live.key
        // The live page hands over only once its loop can show (no flash of the still).
        let hasClip = live.page.clipPath != nil && (!isOnScreen || liveKey != key || readyClips.contains(key))
        let canAnimate = live.prompt != nil && live.page.stillPath != nil && !live.page.text.isEmpty
        return .init(key: key, canAnimate: canAnimate, hasClip: hasClip, isHeld: held.contains(key), isSpent: spent.contains(key))
    }

    private func applyDisplay(_ newDisplay: PreRollPlanner.Display) {
        if display != newDisplay { display = newDisplay }
        let newLiveKey = newDisplay == .live ? onScreen?.key : nil
        guard newLiveKey != liveKey else { return }
        if liveKey != nil, liveKey == onScreen?.key, newDisplay == .clip { holdForCrossfade() }
        if let old = liveKey { recordingUnwatched(old) }
        liveKey = newLiveKey
        if let newLiveKey {
            if fold?.key == newLiveKey { noteMotion(for: newLiveKey) }
            watchFrames(on: newLiveKey)
        } else {
            tripwireTask?.cancel()
            tripwireTask = nil
        }
    }

    private func perform(_ action: PreRollPlanner.Action) {
        switch action {
        case let .animate(key, hidden): animate(key, hidden: hidden)
        case let .reveal(key): reveal(key)
        case .idle: idle()
        }
    }

    private func animate(_ key: PageKey, hidden: Bool) {
        guard let page = [onScreen, behind, completing].compactMap({ $0 }).first(where: { $0.key == key }),
              let prompt = page.prompt, let still = StillImageLoader.data(for: page.page.stillPath)
        else {
            spent.insert(key)
            replan()
            return
        }
        endFlow()
        let generation = tracker.begin(key: Self.trackerKey(key))
        if hidden { bridge.runHidden(generation) }
        flow = Flow(key: key, index: page.page.index, generation: generation, isHidden: hidden, hasFirstFrame: false)
        log("animate p\(page.page.index + 1)\(hidden ? " hidden (pre-roll)" : "")")
        Task { await run(generation, index: page.page.index, still: still, prompt: prompt, hidden: hidden) }
    }

    /// The parent folded to the page running hidden: show its video.
    private func reveal(_ key: PageKey) {
        guard let flow, flow.key == key, revealing != flow.generation else { return }
        let generation = flow.generation
        revealing = generation
        Task {
            let result = try? await bridge.reveal(generation: generation)
            if revealing == generation { revealing = nil }
            guard self.flow?.generation == generation else { return }
            if result?.revealed == true, self.onScreen?.key == key {
                self.flow?.isHidden = false
                log("revealed p\(flow.index + 1)\(result?.hasFirstFrame == true ? " live" : ", first frame still coming")")
            } else if result?.revealed == true {
                // Turned away again while the reveal was on its way: that video must not show.
                endFlow()
                self.flow = nil
            } else {
                // The page no longer knows this flow: start the page over in view.
                endFlow()
                self.flow = nil
            }
            replan()
        }
    }

    /// Nothing needs the session: stop the flow (the connection stays up).
    private func idle() {
        endFlow()
        flow = nil
        Task { try? await bridge.pause() }
    }

    /// Stops what the current flow has running. Synchronous; the caller clears `flow`.
    func endFlow() {
        watchdogTask?.cancel()
        watchdogTask = nil
        recordTask?.cancel()
        recordTask = nil
        tracker.leave()
        Task { await bridge.cancelClip() }
    }

    // MARK: - page flows

    private func run(_ generation: Int, index: Int, still: Data, prompt: String, hidden: Bool) async {
        guard let session else { return }
        let outcome = await session.animate(page: index, still: still, prompt: prompt, generation: generation)
        guard tracker.isCurrent(generation), flow?.generation == generation else { return }
        switch outcome {
        case .started:
            armWatchdog(generation, index: index, still: still, prompt: prompt, hidden: hidden)
        case .superseded:
            break
        case .notReady:
            // Not connected (warming or reconnecting): the session poll replans once it's ready.
            tracker.leave()
            flow = nil
            sessionReady = false
        case let .failed(reason):
            await recover(generation, index: index, still: still, prompt: prompt, hidden: hidden, reason: reason)
        }
    }

    /// No first frame arrived in time: the page mustn't sit preparing forever.
    private func armWatchdog(_ generation: Int, index: Int, still: Data, prompt: String, hidden: Bool) {
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            try? await Task.sleep(for: Self.firstFrameWatchdog)
            guard !Task.isCancelled, let self, self.flow?.generation == generation, self.flow?.hasFirstFrame == false else { return }
            await self.recover(generation, index: index, still: still, prompt: prompt, hidden: hidden,
                               reason: "no first frame within \(Self.firstFrameWatchdog)")
        }
    }

    private func recover(_ generation: Int, index: Int, still: Data, prompt: String, hidden: Bool, reason: String) async {
        switch tracker.stalled(generation: generation) {
        case .ignore:
            return
        case let .retry(next):
            AppLog.scene.error("page \(index + 1) did not come alive (\(reason, privacy: .public)); retrying once")
            // A flow revealed meanwhile stays shown on its retry.
            let stillHidden = flow?.isHidden ?? hidden
            if stillHidden { bridge.runHidden(next) }
            flow?.generation = next
            flow?.hasFirstFrame = false
            await run(next, index: index, still: still, prompt: prompt, hidden: stillHidden)
        case .giveUp:
            AppLog.scene.error("page \(index + 1) did not come alive (\(reason, privacy: .public)); keeping its still")
            log("p\(index + 1) gave up: \(reason)")
            if let key = flow?.key { spent.insert(key) }
            endFlow()
            flow = nil
            replan()
        }
    }

    // MARK: - events

    /// Reads the bridge's events for the controller's whole life (see `kill`).
    private func listen() {
        guard eventsTask == nil else { return }
        eventsTask = Task { [weak self] in
            guard let events = self?.bridge.events else { return }
            for await event in events {
                guard let self else { return }
                await self.handle(event)
            }
        }
    }

    private func handle(_ event: SceneEvent) async {
        guard session != nil else { return }
        switch event {
        case let .firstFrame(generation, _, _, _, background):
            firstFrame(generation: generation, background: background)
        case let .error(code, message, recoverable):
            AppLog.scene.error("live scene error \(code, privacy: .public): \(message, privacy: .public)")
            if recoverable { await session?.reportDisconnected(message) }
        case let .status(value) where value == "disconnected":
            if flow != nil { await session?.reportDisconnected("disconnected") }
        default:
            break
        }
    }

    /// Only the newest flow's first frame counts; a late one from a flow already left is dropped.
    private func firstFrame(generation: Int?, background: Bool) {
        guard var current = flow, current.generation == generation, tracker.firstFrame(generation: generation) else { return }
        watchdogTask?.cancel()
        watchdogTask = nil
        current.hasFirstFrame = true
        if !background { current.isHidden = false }
        flow = current
        if !current.isHidden, current.key == onScreen?.key, let shownAt {
            let ms = Int((ContinuousClock.now - shownAt) / .milliseconds(1))
            self.shownAt = nil
            firstFrameMs.append(ms)
            onFirstFrame(current.index, ms)
        } else if current.isHidden {
            log("p\(current.index + 1) first frame (hidden)")
        }
        recordClip(current)
        replan()
    }

    // MARK: - folds and metrics

    /// A page came on screen: its earlier try no longer counts, and a fold is timed until it moves.
    private func shown(_ page: LivePage, after previous: LivePage?) {
        spent.remove(page.key)
        shownAt = .now
        // A fold opens the next page; turning back or the first words landing aren't folds.
        guard let previous, !previous.page.text.isEmpty, page.page.index == previous.page.index + 1 else { return }
        let outcome: PreRollMetrics.FoldOutcome = if page.page.clipPath != nil {
            .clip
        } else if let flow, flow.key == page.key {
            flow.hasFirstFrame ? .live : .preparing
        } else {
            .cold
        }
        metrics.folded(to: outcome)
        fold = (page.key, .now)
        log("fold to p\(page.page.index + 1): \(outcome)")
    }

    private func noteMotion(for key: PageKey) {
        guard let fold, fold.key == key else { return }
        let ms = Int((ContinuousClock.now - fold.at) / .milliseconds(1))
        metrics.moved(afterMs: ms)
        self.fold = nil
        log("fold → moving in \(ms) ms · \(metrics.summary)")
    }

    /// The live page on screen just got its loop: hand over once it's ready, or after a short wait.
    private func armHandOverTimeout() {
        guard let onScreen, onScreen.page.clipPath != nil, liveKey == onScreen.key, !handOvers.contains(onScreen.key) else { return }
        let key = onScreen.key
        handOvers.insert(key)
        Task { [weak self] in
            try? await Task.sleep(for: Self.handOverTimeout)
            guard let self, !self.readyClips.contains(key) else { return }
            self.log("loop for p\(onScreen.page.index + 1) not ready in \(Self.handOverTimeout); handing over anyway")
            self.readyClips.insert(key)
            self.replan()
        }
    }

    func log(_ line: String) {
        AppLog.scene.info("\(line, privacy: .public)")
        onLog(line)
    }

    /// The session gave up (for example Reactor's one-session-per-model limit answered 429 at
    /// warm-up): pages keep their stills, and the next page shown tries to connect once more.
    private func retryWarmUpIfResting() {
        guard case .fallback = sessionStatus, let server, !isRetryingWarmUp else { return }
        isRetryingWarmUp = true
        log("live session resting; trying to connect again for this page")
        Task { [weak self] in
            guard let self else { return }
            await self.kill()
            await self.warmUp(server: server)
            self.isRetryingWarmUp = false
        }
    }

    private static func trackerKey(_ key: PageKey) -> String { "\(key.id.uuidString)#\(key.version)" }

    // MARK: - session

    /// Mirrors the session's phase into `sessionStatus`, the credit meter and session minutes.
    private func watchSession() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            var last = ContinuousClock.now
            while !Task.isCancelled {
                guard let self, let session = self.session else { return }
                let state = await session.state
                self.credits = await session.credits()
                let now = ContinuousClock.now
                if state.connectedSince != nil { self.metrics.addSessionTime(seconds: (now - last) / .seconds(1)) }
                last = now
                self.noteSessionPhase(state.phase)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func noteSessionPhase(_ phase: SessionPhase) {
        switch phase {
        case .fallback:
            sessionStatus = .fallback("Live pictures are resting; the still pictures carry on.")
            sessionReady = false
        case let .failed(message):
            sessionStatus = .fallback(message)
            sessionReady = false
        case .ready, .animating:
            guard !sessionReady else { return }
            sessionReady = true
            // Connected (again): a flow from before the drop will never finish, so start over.
            if flow != nil {
                endFlow()
                flow = nil
            }
            replan()
        default:
            sessionReady = false
        }
    }
}
