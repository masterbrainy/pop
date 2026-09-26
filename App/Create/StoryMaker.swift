import Foundation
import Observation
import PopKit

/// Live, parent-driven creation along a story path (P-04): the brief plans a path that always
/// ends, the page on screen is written first, and the next pages are fully built ahead of it
/// (words, picture, motion), up to `reader.lookahead` pages, each as soon as the page before it
/// has its words. A direction (speech or typing) re-plans from the next page and rebuilds it,
/// dropping the pages ahead that followed the old version so they're rebuilt from the new one;
/// the page on screen never changes. Folding shows the next page, and building moves one page
/// further ahead. The engine never turns the page; the parent folds.
///
/// Nothing is written until the parent taps Begin: what they type or say before that gathers
/// as ideas for how the story starts. The page behind opens only once its picture is ready.
/// Only the page on screen is animated, live, for as long as it shows.
@MainActor
@Observable
final class StoryMaker {
    /// Whose turn it is. Changing it while listening ends the utterance in progress, so the
    /// next words start fresh under the new speaker.
    var speaker: Speaker = .parent {
        didSet { if oldValue != speaker { speech?.endUtterance() } }
    }
    private(set) var isWorking = false
    private(set) var isListening = false
    /// The words being said right now, still changing.
    private var livePartial = ""
    /// Sentences heard but not yet sent: they go to the story together once the speaker pauses.
    private var spokenSoFar: [String] = []
    @ObservationIgnored private var spokenSpeaker: Speaker?
    @ObservationIgnored private var spokenFlush: Task<Void, Never>?
    /// This long with no new words ends what the parent is saying, and it goes to the story.
    private static let speechPause: Duration = .milliseconds(1_200)

    /// Everything heard since the last direction went out, shown live above the input bar.
    var partial: String {
        (spokenSoFar + [livePartial]).filter { !$0.isEmpty }.joined(separator: " ")
    }
    /// A gentle note for the parent (an unsafe request, a failure), shown briefly.
    private(set) var parentNote: String?
    /// Pages whose picture moderation turned away twice (IMP-10); they show a friendly card, not "Painting…".
    private(set) var unavailablePictures: Set<UUID> = []
    /// Pages whose painting ended without a picture (a failure), so they may open without one;
    /// painting is tried again once they show.
    private(set) var picturelessPages: Set<UUID> = []
    /// Whether the parent has tapped Begin. Until then nothing is written.
    private(set) var hasBegun: Bool
    /// What the parent typed or said before Begin: together they direct the first page.
    private(set) var openingIdeas: [StoryTurnInput] = []
    /// What the first page is waiting on after Begin, for the loading screen; nil once it's
    /// alive (or can't come alive), and from then on.
    enum OpeningStage: Equatable {
        case writing
        case painting
        case animating
    }
    /// The ideas Begin started the story with, shown while the first page is made.
    private(set) var openingIdea: String?
    /// The first page has shown (alive, or as a still once it can't come alive).
    private(set) var hasOpened: Bool
    /// The first page's picture waited too long to come alive; it shows as a still.
    private var openingAnimationTimedOut = false
    /// How long the loading screen waits for the first page to come alive once its picture is ready.
    private static let openingAnimationWait: Duration = .seconds(15)
    /// Latency p50s for the debug overlay.
    private(set) var latency: LatencyTable?

    let reader: BookReader
    let live = LivePageController()
    private(set) var kid: KidProfile
    private(set) var settings: ParentSettings

    @ObservationIgnored private let services: AppServices
    /// The kid's drawing of the hero, if the parent made one, seeded into the bible
    /// the moment the book starts (ROADMAP Phase 8.2).
    @ObservationIgnored private var heroDrawing: HeroDrawing?
    @ObservationIgnored private var motionPrompts: [UUID: String] = [:]
    @ObservationIgnored private var speech: (any SpeechInput)?
    @ObservationIgnored private var speechTask: Task<Void, Never>?
    /// Speech secrets minted ahead of the mic tap, so listening starts without a server wait.
    @ObservationIgnored private let sttSecrets: OneTimeSecrets<RealtimeTranscriber.Secret>?
    /// Whose turn it was when each utterance began (PRD S3).
    @ObservationIgnored private var speakers = SpeakerLedger()
    @ObservationIgnored private var hasEnded = false
    /// One page's words being written (a `path` or `page` call). Its picture and motion are
    /// painted separately, per page id and version, once the words land.
    private struct Build {
        let id = UUID()
        let index: Int
        /// The direction this build follows, if it re-plans the path for one.
        let direction: StoryTurnInput?
    }

    /// The words being written for each page index, until they land; events from a replaced
    /// build are ignored.
    @ObservationIgnored private var builds: [Int: Build] = [:]
    @ObservationIgnored private var buildTasks: [UUID: Task<Void, Never>] = [:]
    /// The picture and motion being painted for each page id.
    @ObservationIgnored private var paintTasks: [UUID: (run: UUID, task: Task<Void, Never>)] = [:]
    /// Pipeline calls go in order, so a newer build for a page always replaces an older one.
    @ObservationIgnored private var pipelineCalls: Task<Void, Never>?
    /// Serializes directions so a second one while one is in flight isn't lost (R-31).
    @ObservationIgnored private let turnQueue = TurnQueue()
    /// A direction is being written or waits in the queue.
    private var directionInFlight = false
    /// The latest direction the parent gave, shown while it's being written.
    private var lastDirection: String?
    /// The last page behind that a direction wrote, so the banner can say it changed.
    private var rewrittenPageId: UUID?
    @ObservationIgnored private var noteTask: Task<Void, Never>?
    @ObservationIgnored private var scriptLog: FileLog?
    @ObservationIgnored private var layerTasks: [UUID: Task<Void, Never>] = [:]
    /// Characters whose reference sheet is being made (or was tried).
    @ObservationIgnored private var referencesRequested: Set<String> = []
    /// Set by the book view: a scripted "finish" step ends and saves the book.
    @ObservationIgnored var onScriptedFinish: @MainActor () async -> Void = {}
    /// Set by the book view: a scripted "pop" step folds to about 90° and back.
    @ObservationIgnored var onScriptedPop: @MainActor () async -> Void = {}

    init(reader: BookReader, kid: KidProfile, settings: ParentSettings, services: AppServices = .shared, heroDrawing: HeroDrawing? = nil) {
        self.reader = reader
        self.kid = kid
        self.settings = settings
        self.services = services
        self.heroDrawing = heroDrawing
        // A draft that already has words, or a scripted run, is under way already.
        let underWay = reader.book.pages.contains { !$0.text.isEmpty } || !LaunchOptions.storyTurns.isEmpty
        hasBegun = underWay
        hasOpened = underWay
        sttSecrets = services.server.map(Self.speechSecrets)
        live.onClip = { [weak self] pageId, url in self?.attachClip(url, to: pageId) }
        live.onFrameFlagged = { [weak self] pageId in
            guard let self else { return }
            // A clip saved before the flag must not replay in the finished book (R-38).
            if self.reader.page(id: pageId)?.clipPath != nil {
                self.reader.updatePage(id: pageId) { $0.with(clipPath: nil) }
            }
            self.note("The moving picture drifted off, so this page keeps its still picture.")
        }
        live.onFirstFrame = { [weak self] index, ms in self?.scriptLog?.append("first frame page \(index + 1) in \(ms) ms") }
        reader.onPageChange = { [weak self] page in self?.pageChanged(to: page) }
        reader.onTurnBlocked = { [weak self] in self?.turnBlocked() }
        reader.canOpenPendingNext = { [weak self] page in self?.isPictureSettled(page) ?? true }
    }

    /// What the first page is still waiting on after Begin, or nil once it can show.
    var openingStage: OpeningStage? {
        guard hasBegun, !hasOpened, let page = reader.currentPage else { return nil }
        if page.text.isEmpty { return .writing }
        if !isPictureSettled(page) { return .painting }
        let canComeAlive = page.stillPath != nil && live.canAnimate && !live.isHeld(page) && !openingAnimationTimedOut
        if canComeAlive, !live.isShowingLive(page) { return .animating }
        return nil
    }

    /// The loading screen saw the first page ready; it doesn't come back.
    func openingShown() {
        hasOpened = true
    }

    /// Whether a page's picture is done: painted, turned away by moderation, or failed.
    func isPictureSettled(_ page: PageContent) -> Bool {
        page.stillPath != nil || unavailablePictures.contains(page.id) || picturelessPages.contains(page.id)
    }

    /// Whether the page behind has its words and its picture, so a turn can open it.
    var isNextPageReady: Bool {
        guard let pending = reader.pendingNext else { return false }
        return !pending.text.isEmpty && isPictureSettled(pending)
    }

    /// What the banner and corner arrow say about the page behind, including a direction that
    /// is still re-writing it (so the parent sees it was heard straight away).
    var nextPageStatus: NextPageStatus {
        NextPageStatus.of(current: reader.currentPage, isEnding: isOnLastPage, pendingNext: reader.pendingNext,
                          direction: directionInFlight ? lastDirection : nil, rewrittenPageId: rewrittenPageId,
                          picturePending: reader.pendingNext.map { !$0.text.isEmpty && !isPictureSettled($0) } ?? false)
    }

    /// A turn came before the page behind was ready: say so, and restart its build if it stopped.
    private func turnBlocked() {
        let hasWords = reader.pendingNext.map { !$0.text.isEmpty } ?? false
        note(hasWords ? "The next page's picture is still being painted. It'll be ready in a moment."
                      : "The next page is still being written. It'll be ready in a moment.")
        ensureBuilds()
    }

    var canCreate: Bool { services.server != nil }

    /// Warms the living page so the first picture animates quickly.
    func begin() async {
        guard let server = services.server else {
            note("Pop! is offline, so new pages can't be made right now. Saved books still work.")
            return
        }
        await sttSecrets?.prefetch()
        // Warm Orbis alongside, so the parent can start telling the story straight away.
        Task { [weak self] in
            await self?.live.warmUp(server: server)
            guard let self else { return }
            self.pageChanged(to: self.reader.currentPage)
        }
        if !LaunchOptions.storyTurns.isEmpty { scriptLog = FileLog(name: "story") }
        if let heroDrawing {
            await seedHero(heroDrawing, server: server)
        }
        if hasBegun { ensureBuilds() }
        await playScriptedTurns()
    }

    /// Whether the page on screen is the story's ending: there's no page behind it, and
    /// Finish saves the book.
    var isOnLastPage: Bool {
        guard reader.book.status == .draft, let page = reader.currentPage, !page.text.isEmpty else { return false }
        return reader.book.bible.isEnding(pageIndex: page.index)
    }

    /// Turns the kid's drawing into the story's hero before the first page is told
    /// (ROADMAP Phase 8.2): the `art` function's `drawing` kind redraws it as a character
    /// reference sheet, which seeds the bible so the story engine draws this character —
    /// and treats it as the protagonist — from the first turn on. A failed or moderation
    /// placeholder result is skipped with a gentle parent note; the story is still told,
    /// just without a hero drawn from the kid's picture.
    private func seedHero(_ drawing: HeroDrawing, server: PopServer) async {
        do {
            let art = try await server.art(HeroCharacter.request(for: drawing, bookId: reader.book.id))
            guard !art.placeholder else {
                note("That drawing couldn't become a character this time, so Pop! will imagine one instead.")
                scriptLog?.append("hero drawing: placeholder returned")
                return
            }
            reader.updateStory { HeroCharacter.seeding($0, drawing: drawing, referencePath: art.path) }
            scriptLog?.append("hero ready in \(art.ms) ms")
        } catch {
            note("That drawing couldn't become a character this time, so Pop! will imagine one instead.")
            scriptLog?.append("hero drawing failed: \(error.localizedDescription)")
        }
    }

    /// Plays `-storyTurns` for automated end-to-end checks, waiting for each turn to finish.
    private func playScriptedTurns() async {
        guard !LaunchOptions.storyTurns.isEmpty else { return }
        let log = scriptLog ?? FileLog(name: "story")
        scriptLog = log
        let started = Date()
        for turn in LaunchOptions.storyTurns {
            switch turn.lowercased() {
            case "fold":
                await waitForPageBehind()
                reader.turnForward()
            case "wait": try? await Task.sleep(for: .seconds(20))
            case "pop":
                log.append("pop: layers \(reader.currentPage?.layers.map { "\($0.cutouts.count) cutouts" } ?? "none")")
                await onScriptedPop()
            case "finish":
                // Let the page on screen go live and record its clip first.
                try? await Task.sleep(for: .seconds(35))
                log.append("finishing: clips \(reader.book.pages.filter { $0.clipPath != nil }.count)/\(reader.book.pages.count)")
                await onScriptedFinish()
                log.append("finished: \(reader.book.title ?? "?") · status \(reader.book.status)")
                return
            case let step where step.hasPrefix("fold during:"):
                // A direction, then a fold before its words land (R-35 a).
                submit(String(turn.dropFirst("fold during:".count)))
                try? await Task.sleep(for: .milliseconds(400))
                log.append("folding mid-rebuild: behind=\(reader.pendingNext.map { "p\($0.index + 1)" } ?? "none")")
                reader.turnForward()
            default: submit(turn)
            }
            try? await Task.sleep(for: .milliseconds(300))
            while isWorking { try? await Task.sleep(for: .milliseconds(250)) }
            AppLog.scene.info("scripted turn done · page \(self.reader.pageNumber)")
            let page = reader.currentPage
            log.append("turn '\(turn)' → page \(reader.pageNumber)/\(reader.book.bible.path.count) still=\(page?.stillPath != nil) motion=\(page.map { motionPrompts[$0.id] != nil } ?? false) behind=\(reader.pendingNext.map { "p\($0.index + 1) still=\($0.stillPath != nil)" } ?? "none") ending=\(isOnLastPage): \(page?.text ?? "")")
        }
        log.append("done in \(Int(Date().timeIntervalSince(started))) s · pages \(reader.book.pages.count) · live \(live.status) · latency \(String(describing: latency))")
        if let note = parentNote { log.append("note: \(note)") }
        // Give the last page time to go live and record its clip, then end the paid session.
        try? await Task.sleep(for: .seconds(40))
        log.append("before end: live \(live.status) · clip \(reader.currentPage?.clipPath != nil) · credits $\(String(format: "%.2f", live.credits))")
        await end()
        log.append("ended")
    }

    /// Before a scripted fold: wait (up to a minute) until the page behind has its words.
    private func waitForPageBehind() async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(60))
        while ContinuousClock.now < deadline, reader.pendingNext == nil, !isOnLastPage, builds[(reader.currentPage?.index ?? -2) + 1] != nil {
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// The app went to the background: end the Orbis session so nothing keeps billing (R-30).
    func pauseLive() async {
        scriptLog?.append("app in background: ending the live session")
        await stopListening(waitingForWords: false)
        await live.kill()
    }

    /// Back in the foreground: warm Orbis again and bring the page on screen back to life.
    func resumeLive() async {
        scriptLog?.append("app active again: warming the live session")
        guard let server = services.server, reader.book.status == .draft else { return }
        await live.warmUp(server: server)
        pageChanged(to: reader.currentPage)
    }

    func end() async {
        hasEnded = true
        buildTasks.values.forEach { $0.cancel() }
        buildTasks = [:]
        builds = [:]
        paintTasks.values.forEach { $0.task.cancel() }
        paintTasks = [:]
        await stopListening(waitingForWords: false)
        await live.kill()
    }

    // MARK: - Input

    func submit(_ text: String, kind: InputKind = .typed) {
        submit(text, kind: kind, by: speaker)
    }

    private func submit(_ text: String, kind: InputKind, by speaker: Speaker) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Late words (a stop still finishing its transcripts) don't start pages after the book ended.
        guard !trimmed.isEmpty, !hasEnded else { return }
        let input = StoryTurnInput(kind: kind, speaker: speaker, text: trimmed)
        guard hasBegun else {
            openingIdeas.append(input)
            return
        }
        lastDirection = trimmed
        enqueue(input)
    }

    /// Begin: the ideas gathered so far direct the first page, and the story starts.
    func beginStory() {
        guard !hasBegun, !hasEnded, let first = openingIdeas.first else { return }
        hasBegun = true
        let text = openingIdeas.map(\.text).joined(separator: " ")
        let kind = openingIdeas.allSatisfy { $0.kind == first.kind } ? first.kind : .typed
        openingIdeas = []
        openingIdea = text
        lastDirection = text
        enqueue(StoryTurnInput(kind: kind, speaker: first.speaker, text: text))
    }

    func removeOpeningIdea(at index: Int) {
        guard openingIdeas.indices.contains(index) else { return }
        openingIdeas.remove(at: index)
    }

    /// Routes a direction through `turnQueue` (R-31): runs it now if none is in flight, else
    /// queues it to run (merged with the same speaker's) once the current one has re-planned.
    private func enqueue(_ input: StoryTurnInput) {
        directionInFlight = true
        refreshWorking()
        Task { [weak self] in
            guard let self, let toRun = await self.turnQueue.submit(input) else { return }
            self.runDirection(toRun)
        }
    }

    func toggleMic() async {
        if isListening {
            await stopListening()
        } else {
            await startListening()
        }
    }

    private static func speechSecrets(from server: any PopServer) -> OneTimeSecrets<RealtimeTranscriber.Secret> {
        OneTimeSecrets(expiry: \.expiresAt) {
            let token = try await server.sttToken()
            return RealtimeTranscriber.Secret(value: token.clientSecret, model: token.model,
                                              expiresAt: Date(timeIntervalSince1970: token.expiresAt))
        }
    }

    /// Listens with Apple's recogniser, which shows words live as they're said and ends each
    /// sentence at a short pause (so the story follows along while the parent talks). OpenAI
    /// Realtime is the fallback when Apple's can't start. The mic shows as on straight away; a
    /// second tap while it starts stops it.
    private func startListening() async {
        guard speech == nil else { return }
        isListening = true
        do {
            try await listen(to: AppleTranscriber())
        } catch SpeechError.microphoneDenied {
            isListening = false
            note(SpeechError.microphoneDenied.localizedDescription)
        } catch {
            AppLog.story.info("on-device listening unavailable: \(error.localizedDescription, privacy: .public)")
            await listenThroughRealtime(after: error)
        }
    }

    /// Apple's recogniser couldn't start: keep the mic on and listen through OpenAI Realtime.
    private func listenThroughRealtime(after error: any Error) async {
        // The parent turned the mic off meanwhile.
        guard isListening, speech == nil else { return }
        guard let sttSecrets else {
            isListening = false
            note(error.localizedDescription)
            return
        }
        scriptLog?.append("speech: on-device recogniser unavailable, listening through Realtime")
        do {
            try await listen(to: RealtimeTranscriber(secrets: sttSecrets))
        } catch {
            if speech == nil { isListening = false }
            note(error.localizedDescription)
        }
    }

    /// Starts `input` and routes what it hears; throws if it couldn't start.
    private func listen(to input: any SpeechInput) async throws {
        speech = input
        let task = Task { [weak self] in
            for await update in input.updates {
                self?.heard(update, from: input)
            }
        }
        speechTask = task
        do {
            try await input.start()
        } catch {
            task.cancel()
            if speech === input { speech = nil }
            throw error
        }
        // Stopped while it was starting.
        if speech !== input { await input.stop(waitingForWords: false) }
    }

    private func heard(_ update: SpeechUpdate, from input: any SpeechInput) {
        switch update {
        case let .began(utterance):
            speakers.began(utterance, by: speaker)
        case let .partial(text):
            guard speech === input || speech == nil else { return }
            livePartial = text
            holdSpoken()
        case let .final(text, utterance):
            spokenSoFar.append(text)
            if spokenSpeaker == nil { spokenSpeaker = speakers.speaker(of: utterance, current: speaker) }
            holdSpoken()
        case let .failed(message):
            guard speech === input else { return }
            speech = nil
            livePartial = ""
            // Apple's recogniser can't run here (it fails to start in the simulator): carry on
            // through OpenAI Realtime instead of stopping.
            if isListening, input is AppleTranscriber {
                Task { [weak self] in await self?.listenThroughRealtime(after: SpeechError.recognizerUnavailable) }
                return
            }
            isListening = false
            flushSpoken()
            note(message)
        }
    }

    /// Waits for a pause in what's being said before sending it; any new words restart the wait.
    private func holdSpoken() {
        spokenFlush?.cancel()
        guard !spokenSoFar.isEmpty else { return }
        spokenFlush = Task { [weak self] in
            try? await Task.sleep(for: Self.speechPause)
            guard !Task.isCancelled else { return }
            self?.flushSpoken()
        }
    }

    /// Sends everything heard so far to the story as one direction (or one opening idea).
    private func flushSpoken() {
        spokenFlush?.cancel()
        spokenFlush = nil
        let text = spokenSoFar.joined(separator: " ")
        let by = spokenSpeaker ?? speaker
        spokenSoFar = []
        spokenSpeaker = nil
        submit(text, kind: .speech, by: by)
    }

    /// Turns the mic off at once. With `waitingForWords` (the parent tapped stop), words already
    /// spoken still become story turns; leaving the book or the app drops them.
    private func stopListening(waitingForWords: Bool = true) async {
        isListening = false
        guard let input = speech else { return }
        speech = nil
        if !waitingForWords {
            speechTask?.cancel()
            speechTask = nil
            spokenFlush?.cancel()
            spokenSoFar = []
            spokenSpeaker = nil
        }
        await input.stop(waitingForWords: waitingForWords)
        // Let the last words arrive (the speech task handles them first), then send them.
        await Task.yield()
        if speech == nil {
            livePartial = ""
            if waitingForWords { flushSpoken() }
        }
    }

    // MARK: - Story path

    /// A direction re-plans the path from the page behind and rebuilds it. While the page on
    /// screen is still empty (the story is just starting), it shapes that page instead.
    private func runDirection(_ input: StoryTurnInput) {
        directionInFlight = true
        guard services.pipeline != nil, let current = reader.currentPage else {
            note("Pop! is offline, so new pages can't be made right now.")
            finishDirection()
            return
        }
        if isOnLastPage {
            note("This is the last page. Tap Finish to save the book.")
            finishDirection()
            return
        }
        let target = current.text.isEmpty ? current.index : current.index + 1
        // Pages further ahead being written now follow the story as it was; they're rebuilt
        // from the new page once it lands.
        for (index, build) in builds where index > target { drop(build) }
        startBuild(at: target, direction: input)
    }

    /// The direction in flight has re-planned (or couldn't): run the next queued one.
    private func finishDirection() {
        Task { [weak self] in
            guard let self else { return }
            if let next = await self.turnQueue.drain() {
                self.runDirection(next)
            } else {
                self.directionInFlight = false
                self.refreshWorking()
            }
        }
    }

    /// Starts whatever the page on screen and the pages ahead still need: words for an empty
    /// page, the next unwritten page ahead (each follows the words of the one before it, so only
    /// one is written at a time), or a picture that never arrived.
    private func ensureBuilds() {
        guard hasBegun, services.pipeline != nil, let current = reader.currentPage else { return }
        let bible = reader.book.bible
        if current.text.isEmpty {
            if builds[current.index] == nil { startBuild(at: current.index, direction: nil) }
            return
        }
        if current.stillPath == nil { paint(current) }
        for offset in 1...reader.lookahead {
            let index = current.index + offset
            guard bible.hasPage(after: index - 1), builds[index] == nil else { return }
            if let page = reader.ahead.first(where: { $0.index == index }) {
                if page.stillPath == nil { paint(page) }
            } else {
                startBuild(at: index, direction: nil)
                return
            }
        }
    }

    /// Writes page `index`: a `path` call to plan or follow a direction, else a `page` call
    /// along the path. Its picture is painted once the words land.
    private func startBuild(at index: Int, direction: StoryTurnInput?) {
        guard let pipeline = services.pipeline else { return }
        let book = reader.book
        // The pages before this one, including those already written ahead but not yet seen.
        let shown = (book.pages + reader.ahead).filter { $0.index < index && !$0.text.isEmpty }
        let request = direction != nil || index >= book.bible.path.count
            ? StoryEngine.pathRequest(book: book, kid: kid, settings: settings, shownPages: shown, index: index, input: direction)
            : StoryEngine.pageRequest(book: book, kid: kid, settings: settings, shownPages: shown, index: index)
        scriptLog?.append("building page \(index + 1) · \(request.mode.rawValue)\(direction == nil ? "" : " for a direction")")
        let build = Build(index: index, direction: direction)
        builds[index] = build
        refreshWorking()
        let started = callPipeline { await pipeline.writePage(request, book: book) }
        buildTasks[build.id] = Task { [weak self] in
            for await event in await started.value {
                self?.apply(event, from: build)
            }
            self?.ended(build)
        }
    }

    /// Paints a page that has words and prepares its motion, unless it's already painting.
    private func paint(_ page: PageContent) {
        guard let pipeline = services.pipeline, paintTasks[page.id] == nil, !unavailablePictures.contains(page.id) else { return }
        let book = reader.book
        let run = UUID()
        picturelessPages.remove(page.id)
        let started = callPipeline { await pipeline.paint(page, book: book) }
        let task = Task { [weak self] in
            var painted = false
            if let stream = await started.value {
                painted = true
                for await event in stream {
                    await self?.applyPaint(event)
                }
            }
            guard let self else { return }
            if self.paintTasks[page.id]?.run == run {
                self.paintTasks[page.id] = nil
                // Painting ended without a picture: don't hold the page back from opening.
                if painted, let latest = self.reader.page(id: page.id), latest.stillPath == nil {
                    self.picturelessPages.insert(page.id)
                }
            }
            self.refreshLatency()
        }
        paintTasks[page.id] = (run, task)
    }

    /// A page behind was replaced by a rewrite: stop its picture, layers and motion.
    private func forget(_ page: PageContent) {
        paintTasks[page.id]?.task.cancel()
        paintTasks[page.id] = nil
        layerTasks[page.id]?.cancel()
        layerTasks[page.id] = nil
        motionPrompts[page.id] = nil
        if let pipeline = services.pipeline {
            _ = callPipeline { await pipeline.cancelPaint(pageId: page.id) }
        }
    }

    /// Runs a pipeline call after the ones before it, so a newer call for a page always
    /// supersedes an older one.
    private func callPipeline<T: Sendable>(_ call: @escaping @Sendable () async -> T) -> Task<T, Never> {
        let previous = pipelineCalls
        let task = Task { () -> T in
            await previous?.value
            return await call()
        }
        pipelineCalls = Task { _ = await task.value }
        return task
    }

    /// A build's stream ended without its words landing (a failure, or it was cancelled).
    private func ended(_ build: Build) {
        buildTasks[build.id] = nil
        guard builds[build.index]?.id == build.id else { return }
        wordsDone(build)
        refreshLatency()
    }

    /// This build's words landed or failed: the page is no longer being written, and a
    /// direction hands the queue on to the next one (its picture keeps painting).
    private func wordsDone(_ build: Build) {
        builds[build.index] = nil
        if build.direction != nil { finishDirection() }
        refreshWorking()
    }

    private func refreshLatency() {
        Task { [weak self] in
            guard let self, let pipeline = self.services.pipeline else { return }
            self.latency = await pipeline.latencyTable()
        }
    }

    /// Stops a build (its page was shown before its words landed).
    private func drop(_ build: Build) {
        builds[build.index] = nil
        buildTasks[build.id]?.cancel()
        buildTasks[build.id] = nil
        if let pipeline = services.pipeline {
            _ = callPipeline { await pipeline.cancel(pageIndex: build.index) }
        }
    }

    private func refreshWorking() {
        let writingCurrent = reader.currentPage.map { $0.text.isEmpty && builds[$0.index] != nil } ?? false
        isWorking = directionInFlight || writingCurrent
    }

    private func apply(_ event: PagePipelineEvent, from build: Build) {
        guard builds[build.index]?.id == build.id else { return }
        switch event {
        case let .pageWritten(outcome):
            written(outcome, by: build)
        case let .failed(message):
            fail(message)
        case .stillReady, .motionReady, .pictureUnavailable:
            break
        }
    }

    /// A picture or motion prompt applies only to the page (and version) it was made for.
    private func applyPaint(_ event: PagePipelineEvent) async {
        switch event {
        case let .stillReady(key, path, url):
            guard reader.page(id: key.id)?.version == key.version else { return }
            makeReferences(fromStill: path)
            await storeStill(url: url, for: key)
        case let .motionReady(key, prompt):
            guard let page = reader.page(id: key.id), page.version == key.version else { return }
            motionPrompts[page.id] = prompt
            if page.id == reader.currentPage?.id { animate(page) }
        case let .pictureUnavailable(key):
            guard reader.page(id: key.id)?.version == key.version else { return }
            unavailablePictures.insert(key.id)
            note("That picture didn't turn out right, so this page is one to imagine.")
        case let .failed(message):
            fail(message)
        case .pageWritten:
            break
        }
    }

    private func fail(_ message: String) {
        let lines = message.split(separator: "\n", maxSplits: 1).map(String.init)
        if lines.count > 1 { scriptLog?.append("failure detail: \(lines[1])") }
        note(lines.first ?? message)
    }

    /// A page's words arrived: an empty page on screen takes them, otherwise they become the
    /// page behind. A page the reader has already seen is never changed.
    private func written(_ outcome: PathOutcome, by build: Build) {
        // Take only the bible, onto the latest book: pages may have gained pictures meanwhile.
        reader.updateStory { $0.with(bible: outcome.book.bible.carryingReferences(from: $0.bible)) }
        if let message = outcome.parentNote { note(message) }
        if let page = outcome.page {
            switch reader.place(page) {
            case let .onScreen(placed):
                paint(placed)
            case let .behind(placed, replaced):
                replaced.forEach(forget)
                // Pages further ahead being written followed the page just replaced.
                if !replaced.isEmpty {
                    for (index, other) in builds where index > placed.index && other.id != build.id { drop(other) }
                }
                if build.direction != nil { rewrittenPageId = placed.id }
                paint(placed)
            case .dropped:
                scriptLog?.append("page \(page.index + 1) written but no longer needed")
            }
            scriptLog?.append("page \(page.index + 1)/\(reader.book.bible.path.count) written\(build.direction == nil ? "" : " for a direction")")
        }
        // The next direction can go as soon as these words land; the picture keeps going.
        wordsDone(build)
        refreshLatency()
        ensureBuilds()
    }

    /// Makes a reference sheet, from this page's picture, for each character that has none,
    /// so later pages draw them the same way (PRD S6).
    private func makeReferences(fromStill stillPath: String) {
        guard let server = services.server else { return }
        let bookId = reader.book.id
        for character in CharacterReferences.missing(in: reader.book.bible, alreadyRequested: referencesRequested) {
            referencesRequested.insert(character.id)
            let request = CharacterReferences.request(for: character, bookId: bookId, fromStill: stillPath)
            Task { [weak self] in
                do {
                    let art = try await server.art(request)
                    guard let self, !art.placeholder else { return }
                    self.reader.updateStory { $0.with(bible: $0.bible.settingReference(art.path, for: character.id)) }
                    self.scriptLog?.append("reference ready for \(character.id) in \(art.ms) ms")
                } catch {
                    self?.scriptLog?.append("reference failed for \(character.id): \(error.localizedDescription)")
                    self?.referencesRequested.remove(character.id)
                }
            }
        }
    }

    private func storeStill(url: String, for key: PageKey) async {
        guard let remote = URL(string: url), let page = reader.page(id: key.id), page.version == key.version else { return }
        do {
            // Named by page id and version: a rebuilt page behind reuses its index.
            let path = try await services.media.store(from: remote, named: "\(reader.book.id)-p\(page.index)-\(page.id.uuidString.prefix(8))-v\(page.version).png")
            // Only onto the same page and version; a page replaced meanwhile drops it.
            if let updated = reader.updatePage(id: key.id, version: key.version, { $0.with(stillPath: path) }) {
                prepareLayers(for: updated)
                if !hasOpened, updated.id == reader.currentPage?.id { limitOpeningAnimationWait() }
            }
        } catch {
            note("A picture didn't arrive. It will be tried again on the next turn.")
        }
    }

    /// Pop-up layers for a page with a picture, made in the background (Phase 4).
    /// Layers made at the very start compete with the page, next-page and reference pictures,
    /// and the image service sometimes turns them away, so a failure is tried once more.
    private static let layerRetryDelay: Duration = .seconds(12)

    private func prepareLayers(for page: PageContent, isRetry: Bool = false) {
        guard let server = services.server else { return }
        layerTasks[page.id]?.cancel()
        let book = reader.book
        let media = services.media
        layerTasks[page.id] = Task { [weak self] in
            if isRetry { try? await Task.sleep(for: Self.layerRetryDelay) }
            do {
                let layers = try await LayerMaker.makeLayers(for: page, book: book, server: server, media: media)
                guard !Task.isCancelled, let self else { return }
                // Only onto the page (and version) these layers were drawn for.
                guard self.reader.updatePage(id: page.id, version: page.version, { $0.with(layers: layers) }) != nil else { return }
                self.scriptLog?.append("layers ready for page \(page.index + 1): \(layers.cutouts.count) cutouts")
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.scriptLog?.append("layers failed for page \(page.index + 1)\(isRetry ? " again" : ""): \((error as? ServerError)?.serverDetail ?? error.localizedDescription)")
                if !isRetry { self.prepareLayers(for: page, isRetry: true) }
            }
        }
    }

    /// The first page's picture is ready: give it `openingAnimationWait` to come alive, then
    /// let the loading screen show it as a still.
    private func limitOpeningAnimationWait() {
        Task { [weak self] in
            try? await Task.sleep(for: Self.openingAnimationWait)
            self?.openingAnimationTimedOut = true
        }
    }

    // MARK: - Living page

    private func pageChanged(to page: PageContent?) {
        Task { await live.pageWillChange() }
        guard let page else { return }
        // Folded while a direction was re-building this page: the old page behind shows as it
        // was, and the direction applies to the new page behind instead.
        // Once its words have landed, the rebuilt page is what just showed, so the build only
        // finishes its picture (R-40).
        // A build stays in `builds` only until its words land, so this never re-applies a direction.
        if !page.text.isEmpty, let build = builds[page.index], let direction = build.direction {
            scriptLog?.append("folded mid-rebuild: the direction moves to page \(page.index + 2)")
            drop(build)
            note("Your change will show on the next page.")
            runDirection(direction)
        }
        refreshWorking()
        ensureBuilds()
        animate(page)
    }

    private func animate(_ page: PageContent) {
        guard page.clipPath == nil, let prompt = motionPrompts[page.id],
              let path = page.stillPath, let data = StillImageLoader.data(for: path)
        else { return }
        Task { await live.show(page, still: data, prompt: prompt) }
    }

    /// Before saving: animate and record any page whose clip isn't complete yet (ROADMAP
    /// Phase 5), so the saved book replays every page. Pages without a picture or motion
    /// prompt keep their still. Each page waits at most `perPage`, and nothing waits past
    /// `deadline`: pages left over keep their still (IMP-13).
    func completeClips(perPage: Duration = .seconds(45), until deadline: ContinuousClock.Instant? = nil) async -> (recorded: Int, missing: Int) {
        var recorded = 0
        var missing = 0
        for page in reader.book.pages where page.clipPath == nil && !page.text.isEmpty && !live.isHeld(page) {
            let hasTime = deadline.map { ContinuousClock.now < $0 } ?? true
            guard hasTime, live.canAnimate, let prompt = motionPrompts[page.id], let data = StillImageLoader.data(for: page.stillPath) else {
                missing += 1
                continue
            }
            await live.pageWillChange()
            await live.show(page, still: data, prompt: prompt)
            let pageDeadline = min(ContinuousClock.now.advanced(by: perPage), deadline ?? .now.advanced(by: perPage))
            while ContinuousClock.now < pageDeadline, reader.page(id: page.id)?.clipPath == nil {
                try? await Task.sleep(for: .milliseconds(500))
            }
            if reader.page(id: page.id)?.clipPath != nil { recorded += 1 } else { missing += 1 }
        }
        scriptLog?.append("completed clips: recorded \(recorded), still missing \(missing)")
        return (recorded, missing)
    }

    /// Adds a line to the scripted run's log (automation only).
    func record(_ line: String) {
        scriptLog?.append(line)
    }

    private func attachClip(_ url: URL, to pageId: UUID) {
        reader.updatePage(id: pageId) { $0.with(clipPath: url.path(percentEncoded: false)) }
    }

    private func note(_ message: String) {
        scriptLog?.append("note: \(message)")
        AppLog.scene.info("parent note: \(message, privacy: .public)")
        parentNote = message
        noteTask?.cancel()
        noteTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            self?.parentNote = nil
        }
    }

    func update(kid: KidProfile, settings: ParentSettings) {
        self.kid = kid
        self.settings = settings
    }
}
