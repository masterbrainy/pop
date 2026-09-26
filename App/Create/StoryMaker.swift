import Foundation
import Observation
import PopKit

/// Live, parent-driven creation along a story path (P-04). No page until prompted: the book
/// opens empty, and the parent's first words (spoken or typed) plan a path that always ends and
/// write page 1. No page until painted: a page shows only with its picture (or once its picture
/// can't come), and the next page is fully built behind it (words, picture, motion). A direction
/// re-plans from the page behind and rebuilds it; the page on screen never changes. Folding
/// shows the page behind once it's ready, and the one after it starts building. The engine
/// never turns the page; the parent folds.
@MainActor
@Observable
final class StoryMaker {
    /// An opening prompt that didn't work, handed back to the text field (each one is new).
    struct ReturnedPrompt: Equatable {
        let id = UUID()
        let text: String
    }

    /// Whose turn it is. Changing it while listening ends the utterance in progress, so the
    /// next words start fresh under the new speaker.
    var speaker: Speaker = .parent {
        didSet { if oldValue != speaker { speech?.endUtterance() } }
    }
    private(set) var isWorking = false
    private(set) var isListening = false
    private(set) var partial = ""
    /// A gentle note for the parent (an unsafe request, a failure), shown briefly.
    private(set) var parentNote: String?
    /// The opening prompt while page 1 is being made: nil before it, and once page 1 shows.
    private(set) var openingPrompt: String?
    /// Page 1 has taken a while; the left page says "Almost there…".
    private(set) var isOpeningSlow = false
    /// The kid's drawing is still becoming the hero.
    private(set) var isHeroPending = false
    private(set) var returnedPrompt: ReturnedPrompt?
    /// Each page version's picture and motion ("no page until painted"). Moderation's
    /// unavailable pictures (IMP-10) and given-up pictures show the imagine card.
    private var pictureStates: [PageKey: PictureState] = [:]
    private var motionStates: [PageKey: MotionState] = [:]
    /// Bumped when a page's motion grace ends, so readiness (which depends on the time) is read again.
    private var readinessTick = 0
    /// Pages the parent has seen: page 1 once it's painted, every later page by a turn.
    private var shownPageIds: Set<UUID> = []
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
    /// Motion prompts by page version, so a rewritten page never animates with its old prompt.
    @ObservationIgnored private var motionPrompts: [PageKey: String] = [:]
    @ObservationIgnored private var speech: (any SpeechInput)?
    @ObservationIgnored private var speechTask: Task<Void, Never>?
    /// Speech secrets minted ahead of the mic tap, so listening starts without a server wait.
    @ObservationIgnored private let sttSecrets: OneTimeSecrets<RealtimeTranscriber.Secret>?
    /// Whose turn it was when each utterance began (PRD S3).
    @ObservationIgnored private var speakers = SpeakerLedger()
    @ObservationIgnored private var hasEnded = false
    /// The kid's drawing becoming the hero; page 1 waits for it.
    @ObservationIgnored private var heroTask: Task<Void, Never>?
    /// The parent has sent the opening prompt (Orbis warms from then on).
    @ObservationIgnored private var hasPrompted = false
    @ObservationIgnored private var openingSubmittedAt: ContinuousClock.Instant?
    /// Page 1's words calls so far for this opening prompt (it's tried twice).
    @ObservationIgnored private var openingAttempt = 0
    @ObservationIgnored private var openingSlowTask: Task<Void, Never>?
    @ObservationIgnored private var stillStoredAt: [PageKey: Date] = [:]
    /// Each painting page's deadline, after which it shows without its picture.
    @ObservationIgnored private var giveUpTimers: [PageKey: Task<Void, Never>] = [:]
    /// Pages painted again because their still couldn't be stored (once each).
    @ObservationIgnored private var storeRepainted: Set<PageKey> = []
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
    /// Pages whose question was answered, skipped, or made stale by a re-plan (IMP-25).
    private var settledQuestions: Set<PageKey> = []
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
        sttSecrets = services.server.map(Self.speechSecrets)
        live.onClip = { [weak self] key, url in self?.attachClip(url, to: key) }
        live.onFrameFlagged = { [weak self] key in
            guard let self else { return }
            // A clip saved before the flag must not replay in the finished book (R-38).
            if let clip = self.reader.page(id: key.id)?.clipPath,
               self.reader.updatePage(id: key.id, version: key.version, { $0.with(clipPath: nil) }) != nil {
                try? FileManager.default.removeItem(atPath: clip)
            }
            self.refreshLive()
            self.note("The moving picture drifted off, so this page keeps its still picture.")
        }
        live.onFirstFrame = { [weak self] index, ms in self?.scriptLog?.append("first frame page \(index + 1) in \(ms) ms") }
        live.onLog = { [weak self] line in self?.scriptLog?.append("live: \(line)") }
        reader.onPageChange = { [weak self] page in self?.pageChanged(to: page) }
        reader.onTurnBlocked = { [weak self] in self?.turnBlocked() }
        reader.canOpenPending = { [weak self] pending in self?.canOpen(pending) ?? false }
        shownPageIds = Set(reader.book.pages.filter { !$0.text.isEmpty }.map(\.id))
    }

    /// Whether the page behind is ready, so a turn can open it.
    var isNextPageReady: Bool {
        guard let pending = reader.pendingNext else { return false }
        return canOpen(pending)
    }

    /// What the banner and corner arrow say about the page behind, including a direction that
    /// is still re-writing it (so the parent sees it was heard straight away).
    var nextPageStatus: NextPageStatus {
        let pending = reader.pendingNext
        return NextPageStatus.of(
            current: reader.currentPage, currentShown: isShown(reader.currentPage), isEnding: isOnLastPage, pendingNext: pending,
            behindReady: pending.map { readiness(of: $0, requiresMotion: true).isReady } ?? false,
            direction: directionInFlight ? lastDirection : nil, rewrittenPageId: rewrittenPageId, lastDirection: lastDirection
        )
    }

    /// A turn came before the page behind was ready: say so, and restart its build if it stopped.
    private func turnBlocked() {
        guard isShown(reader.currentPage) else { return }
        let hasWords = reader.pendingNext.map { !$0.text.isEmpty } ?? false
        note(hasWords ? "The next page is still being painted. It'll be ready in a moment."
                      : "The next page is still being written. It'll be ready in a moment.")
        ensureBuilds()
    }

    var canCreate: Bool { services.server != nil }

    // MARK: - The page's question (IMP-25)

    /// The question under the page on screen (once it shows), while it still steers what happens next.
    var activeQuestion: ActiveQuestion? {
        QuestionStrip.visible(page: shownPage, isEnding: isOnLastPage, directionInFlight: directionInFlight, settled: settledQuestions)
    }

    /// A tapped tile: the path's own next beat just hides the question (the page behind is
    /// already being built that way); any other re-plans the page behind as the kid's turn.
    func answer(_ choice: StoryChoice) {
        guard !hasEnded, activeQuestion?.choices.contains(choice) == true else { return }
        settleQuestion()
        scriptLog?.append("answered: \(choice.label)\(choice.followsPath ? " (the path's own next beat)" : "")")
        guard let input = QuestionStrip.input(for: choice) else { return }
        lastDirection = choice.label
        enqueue(input)
    }

    func skipQuestion() {
        settleQuestion()
    }

    /// "Something else": the kid says their own idea, so the input bar comes back on the kid's turn with the mic on.
    func somethingElse() async {
        settleQuestion()
        speaker = .kid
        if !isListening { await startListening() }
    }

    private func settleQuestion() {
        guard let page = shownPage else { return }
        settledQuestions.insert(page.key)
    }

    /// Gets ready for the opening prompt: speech secrets, and the kid's drawing becoming the
    /// hero. No page is written, and Orbis doesn't warm, until the parent starts the story.
    func begin() async {
        guard let server = services.server else {
            note("Pop! is offline, so new pages can't be made right now. Saved books still work.")
            return
        }
        if !LaunchOptions.storyTurns.isEmpty { scriptLog = FileLog(name: "story") }
        if let heroDrawing {
            isHeroPending = true
            heroTask = Task { [weak self] in
                await self?.seedHero(heroDrawing, server: server)
                self?.isHeroPending = false
            }
        }
        await sttSecrets?.prefetch()
        await playScriptedTurns()
    }

    /// Whether the page on screen is the story's ending: there's no page behind it, and
    /// Finish saves the book.
    var isOnLastPage: Bool {
        guard reader.book.status == .draft, let page = reader.currentPage, !page.text.isEmpty, isShown(page) else { return false }
        return reader.book.bible.isEnding(pageIndex: page.index)
    }

    // MARK: - Readiness (no page until prompted, no page until painted)

    /// The page on screen once the parent may see it: nil until page 1 is painted.
    var shownPage: PageContent? {
        guard let page = reader.currentPage, shownPageIds.contains(page.id) else { return nil }
        return page
    }

    /// Whether any page has been shown (Finish and saving count only shown pages).
    var hasShownPage: Bool { !shownPageIds.isEmpty }

    var openingState: OpeningState {
        if shownPage != nil { return .shown }
        let current = reader.currentPage
        return OpeningState.of(current: current, isWritingFirst: openingPrompt != nil, heroPending: isHeroPending,
                               readiness: current.map { readiness(of: $0, requiresMotion: false) } ?? .writing)
    }

    /// What the left page says until page 1 shows.
    var openingText: String? {
        openingState.leftPage(prompt: openingPrompt, isSlow: isOpeningSlow)
    }

    /// A page whose picture can't come (moderation, a failure, or its deadline): the imagine card.
    func showsImagineCard(for page: PageContent?) -> Bool {
        guard let page, page.stillPath == nil else { return false }
        switch pictureStates[page.key] {
        case .unavailable, .gaveUp: return true
        default: return false
        }
    }

    private func isShown(_ page: PageContent?) -> Bool {
        page.map { shownPageIds.contains($0.id) } ?? false
    }

    private func readiness(of page: PageContent, requiresMotion: Bool) -> PageReadiness {
        _ = readinessTick
        let picture = page.stillPath != nil ? .stored : pictureStates[page.key] ?? .painting
        return PageReadiness.of(page: page, picture: picture, motion: motionStates[page.key] ?? .pending,
                                stillStoredAt: stillStoredAt[page.key], now: .now, requiresMotion: requiresMotion)
    }

    /// A turn opens the page behind only from a shown page, and only once the page behind is ready.
    private func canOpen(_ pending: PageContent) -> Bool {
        isShown(reader.currentPage) && readiness(of: pending, requiresMotion: true).isReady
    }

    /// Shows page 1 once it's painted, and keeps the working spinner in step.
    private func refreshReadiness() {
        if let current = reader.currentPage, !current.text.isEmpty, !isShown(current),
           readiness(of: current, requiresMotion: false).isReady {
            reveal(current)
        }
        refreshWorking()
    }

    /// The page on screen is ready: show it (words and picture together), start painting the
    /// page behind, and bring it to life.
    private func reveal(_ page: PageContent) {
        shownPageIds.insert(page.id)
        if let submitted = openingSubmittedAt {
            let ms = Int((ContinuousClock.now - submitted) / .milliseconds(1))
            scriptLog?.append("page \(page.index + 1) shown in \(ms) ms\(page.stillPath == nil ? " (no picture)" : "")")
        }
        endOpening()
        refreshWorking()
        ensureBuilds()
        refreshLive()
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
            case let step where step.hasPrefix("choose:"):
                // Taps the page's nth choice (1-based), for scripted checks of IMP-25.
                let choices = activeQuestion?.choices ?? []
                let number = Int(step.dropFirst("choose:".count)) ?? 0
                log.append("question: \(activeQuestion?.ask ?? "none") · \(choices.map(\.label).joined(separator: " / "))")
                if choices.indices.contains(number - 1) { answer(choices[number - 1]) }
            case "skip":
                skipQuestion()
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
            log.append("turn '\(turn)' → page \(reader.pageNumber)/\(reader.book.bible.path.count) still=\(page?.stillPath != nil) motion=\(page.map { motionPrompts[$0.key] != nil } ?? false) behind=\(reader.pendingNext.map { "p\($0.index + 1) still=\($0.stillPath != nil)" } ?? "none") ending=\(isOnLastPage): \(page?.text ?? "")")
        }
        log.append("done in \(Int(Date().timeIntervalSince(started))) s · pages \(reader.book.pages.count) · live \(live.status) · latency \(String(describing: latency))")
        if let note = parentNote { log.append("note: \(note)") }
        // Give the last page time to go live and record its clip, then end the paid session.
        try? await Task.sleep(for: .seconds(40))
        log.append("before end: live \(live.status) · clip \(reader.currentPage?.clipPath != nil) · credits $\(String(format: "%.2f", live.credits))")
        await end()
        log.append("ended")
    }

    /// Before a scripted fold: wait until the page behind is ready (painted, or past its deadline).
    private func waitForPageBehind() async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(PaintDeadlines.waitForPageBehind))
        while ContinuousClock.now < deadline, !isNextPageReady, !isOnLastPage {
            // Nothing is coming (its words failed): the fold will say so.
            if reader.pendingNext == nil, builds[(reader.currentPage?.index ?? -2) + 1] == nil, !directionInFlight { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// The app went to the background: end the Orbis session so nothing keeps billing (R-30).
    func pauseLive() async {
        scriptLog?.append("app in background: ending the live session")
        await stopListening(waitingForWords: false)
        await live.kill()
    }

    /// Back in the foreground: warm Orbis again and bring the page on screen back to life
    /// (only once the story has started: Orbis warms from the opening prompt).
    func resumeLive() async {
        guard let server = services.server, reader.book.status == .draft, hasPrompted else { return }
        scriptLog?.append("app active again: warming the live session")
        await live.warmUp(server: server)
        pageChanged(to: reader.currentPage)
    }

    func end() async {
        hasEnded = true
        heroTask?.cancel()
        openingSlowTask?.cancel()
        giveUpTimers.values.forEach { $0.cancel() }
        giveUpTimers = [:]
        buildTasks.values.forEach { $0.cancel() }
        buildTasks = [:]
        builds = [:]
        paintTasks.values.forEach { $0.task.cancel() }
        paintTasks = [:]
        await stopListening(waitingForWords: false)
        scriptLog?.append("pre-roll: \(live.metrics.summary)")
        await live.kill()
        // The page behind is never saved, so its pre-recorded loop goes.
        if let clip = reader.pendingNext?.clipPath { try? FileManager.default.removeItem(atPath: clip) }
    }

    // MARK: - Input

    func submit(_ text: String, kind: InputKind = .typed) {
        submit(text, kind: kind, by: speaker)
    }

    private func submit(_ text: String, kind: InputKind, by speaker: Speaker) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Late words (a stop still finishing its transcripts) don't start pages after the book ended.
        guard !trimmed.isEmpty, !hasEnded else { return }
        // A direction re-plans what happens next, so the page's question is stale (IMP-25).
        settleQuestion()
        lastDirection = trimmed
        if reader.currentPage?.text.isEmpty == true, openingPrompt == nil { startOpening(with: trimmed) }
        enqueue(StoryTurnInput(kind: kind, speaker: speaker, text: trimmed))
    }

    /// The opening prompt came in: page 1 is made from it, and Orbis starts warming now
    /// (connecting is free; billing starts once it's ready), hidden behind page 1's words and picture.
    private func startOpening(with prompt: String) {
        openingPrompt = prompt
        openingSubmittedAt = .now
        openingAttempt = 0
        returnedPrompt = nil
        isOpeningSlow = false
        openingSlowTask?.cancel()
        openingSlowTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(PaintDeadlines.firstPageSlow))
            guard !Task.isCancelled else { return }
            self?.isOpeningSlow = true
        }
        startLiveIfNeeded()
        refreshWorking()
    }

    /// Page 1 showed, or its prompt didn't work: the book is no longer opening.
    private func endOpening() {
        openingPrompt = nil
        openingSubmittedAt = nil
        openingSlowTask?.cancel()
        openingSlowTask = nil
        isOpeningSlow = false
    }

    private func startLiveIfNeeded() {
        guard !hasPrompted, let server = services.server else { return }
        hasPrompted = true
        Task { [weak self] in
            await self?.live.warmUp(server: server)
            self?.refreshLive()
        }
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

    /// Listens through OpenAI Realtime, or Apple's on-device recogniser if Realtime can't start.
    /// The mic shows as on straight away; a second tap while it starts stops it.
    private func startListening() async {
        guard speech == nil else { return }
        isListening = true
        do {
            if let sttSecrets {
                do {
                    try await listen(to: RealtimeTranscriber(secrets: sttSecrets))
                    return
                } catch SpeechError.microphoneDenied {
                    throw SpeechError.microphoneDenied
                } catch {
                    AppLog.story.info("realtime listening unavailable: \(error.localizedDescription, privacy: .public)")
                    guard isListening else { return }
                    await listenOnDevice()
                    return
                }
            }
            try await listen(to: AppleTranscriber())
        } catch {
            if speech == nil { isListening = false }
            note(error.localizedDescription)
        }
    }

    /// Realtime couldn't connect (no secret, or its socket never opened): keep the mic on and
    /// listen with Apple's on-device recogniser instead.
    private func listenOnDevice() async {
        // The parent turned the mic off meanwhile.
        guard isListening, speech == nil else { return }
        scriptLog?.append("speech: realtime never connected, listening on the device")
        do {
            try await listen(to: AppleTranscriber())
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
            if speech === input || speech == nil { partial = text }
        case let .final(text, utterance):
            submit(text, kind: .speech, by: speakers.speaker(of: utterance, current: speaker))
        case let .failed(message):
            guard speech === input else { return }
            speech = nil
            partial = ""
            if isListening, let realtime = input as? RealtimeTranscriber, !realtime.hasOpened {
                Task { [weak self] in await self?.listenOnDevice() }
                return
            }
            isListening = false
            note(message)
        }
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
        }
        await input.stop(waitingForWords: waitingForWords)
        if speech == nil { partial = "" }
    }

    // MARK: - Story path

    /// A direction re-plans the path from the page behind and rebuilds it. While the page on
    /// screen is still empty, it's the opening prompt: it plans the path and writes page 1.
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
        if current.text.isEmpty {
            writeFirstPage(input)
            return
        }
        startBuild(at: current.index + 1, direction: input)
    }

    /// Page 1 from the opening prompt, once the kid's drawing is the hero (if there is one).
    private func writeFirstPage(_ input: StoryTurnInput) {
        // A prompt queued behind one that didn't work opens the book afresh.
        if openingPrompt == nil { startOpening(with: input.text) }
        Task { [weak self] in
            if let hero = self?.heroTask { await hero.value }
            guard let self, !self.hasEnded else { return }
            self.openingAttempt += 1
            self.startBuild(at: 0, direction: input)
        }
    }

    /// Page 1's words failed: try once more, then hand the prompt back with a note. True
    /// while it's being tried again (the direction stays in flight).
    private func retryOpening(_ input: StoryTurnInput) -> Bool {
        guard !hasEnded else { return false }
        if openingAttempt < 2 {
            scriptLog?.append("page 1 failed, trying again")
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard let self, !self.hasEnded else { return }
                self.openingAttempt += 1
                self.startBuild(at: 0, direction: input)
            }
            return true
        }
        scriptLog?.append("page 1 failed twice: back to the empty book")
        endOpening()
        returnedPrompt = ReturnedPrompt(text: input.text)
        note("That didn't work. Try telling it again.")
        return false
    }

    /// A words call for page 1 from the opening prompt (while page 1 is still empty).
    private func isOpening(_ build: Build) -> Bool {
        build.index == 0 && build.direction != nil && reader.book.pages.first?.text.isEmpty == true
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

    /// Starts whatever the page on screen and the page behind still need: the next page
    /// behind, or a picture that never arrived. An empty book needs nothing: page 1 is started
    /// only by the opening prompt (`runDirection`).
    private func ensureBuilds() {
        guard services.pipeline != nil, let current = reader.currentPage, !current.text.isEmpty else { return }
        let bible = reader.book.bible
        if current.stillPath == nil { paint(current) }
        let behind = current.index + 1
        guard bible.hasPage(after: current.index), builds[behind] == nil else { return }
        if let pending = reader.pendingNext, pending.index == behind {
            // The page behind paints once the page on screen shows, so page 1's picture never
            // waits behind page 2's.
            if pending.stillPath == nil, isShown(current) { paint(pending) }
        } else {
            startBuild(at: behind, direction: nil)
        }
    }

    /// Writes page `index`: a `path` call to plan or follow a direction, else a `page` call
    /// along the path. Its picture is painted once the words land.
    private func startBuild(at index: Int, direction: StoryTurnInput?) {
        guard let pipeline = services.pipeline else { return }
        let book = reader.book
        let shown = book.pages.filter { $0.index < index && !$0.text.isEmpty }
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
        guard let pipeline = services.pipeline, paintTasks[page.id] == nil, pictureStates[page.key] != .unavailable else { return }
        scheduleGiveUp(for: page)
        let book = reader.book
        let run = UUID()
        let started = callPipeline { await pipeline.paint(page, book: book) }
        let task = Task { [weak self] in
            if let stream = await started.value {
                for await event in stream {
                    await self?.applyPaint(event)
                }
            }
            if self?.paintTasks[page.id]?.run == run { self?.paintTasks[page.id] = nil }
            self?.refreshLatency()
        }
        paintTasks[page.id] = (run, task)
    }

    /// A page behind was replaced by a rewrite: stop its picture, layers and motion.
    private func forget(_ page: PageContent) {
        paintTasks[page.id]?.task.cancel()
        paintTasks[page.id] = nil
        layerTasks[page.id]?.cancel()
        layerTasks[page.id] = nil
        motionPrompts = motionPrompts.filter { $0.key.id != page.id }
        // A loop pre-recorded for the replaced page is never shown.
        if let clip = page.clipPath { try? FileManager.default.removeItem(atPath: clip) }
        if let pipeline = services.pipeline {
            _ = callPipeline { await pipeline.cancelPaint(pageId: page.id) }
        }
        refreshLive()
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
        if isOpening(build), let input = build.direction, retryOpening(input) {
            builds[build.index] = nil
            return
        }
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

    /// The spinner: a direction is being written, or page 1 is being made and isn't shown yet.
    private func refreshWorking() {
        let makingFirstPage = openingPrompt != nil && !isShown(reader.currentPage)
        isWorking = directionInFlight || makingFirstPage
    }

    private func apply(_ event: PagePipelineEvent, from build: Build) {
        guard builds[build.index]?.id == build.id else { return }
        switch event {
        case let .pageWritten(outcome):
            written(outcome, by: build)
        case let .failed(message) where isOpening(build):
            // Page 1 is tried again, and only its final failure speaks (`retryOpening`).
            scriptLog?.append("page 1 words failed: \(message.replacingOccurrences(of: "\n", with: " · "))")
        case let .failed(message):
            fail(message)
        case .stillReady, .motionReady, .pictureUnavailable, .paintFailed, .motionFailed:
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
            motionPrompts[key] = prompt
            motionStates[key] = .ready
            // The page on screen animates, or the page behind is pre-animated once it's ready.
            refreshLive()
            refreshReadiness()
        case let .motionFailed(key):
            guard let page = reader.page(id: key.id), page.version == key.version else { return }
            scriptLog?.append("motion prompt failed for page \(page.index + 1): it keeps its still")
            motionStates[key] = .failed
            refreshReadiness()
        case let .pictureUnavailable(key):
            guard reader.page(id: key.id)?.version == key.version else { return }
            pictureStates[key] = .unavailable
            giveUpTimers[key]?.cancel()
            note("That picture didn't turn out right, so this page is one to imagine.")
            refreshReadiness()
        case let .paintFailed(key, detail):
            scriptLog?.append("picture failed twice: \(detail.replacingOccurrences(of: "\n", with: " · "))")
            giveUp(on: key, because: "A picture didn't arrive, so this page is one to imagine for now.")
        case let .failed(message):
            fail(message)
        case .pageWritten:
            break
        }
    }

    /// Past this deadline the page shows without its picture (the imagine card), so a slow
    /// picture never holds the book; a still that lands later still shows (`PaintDeadlines`).
    private func scheduleGiveUp(for page: PageContent) {
        let key = page.key
        guard giveUpTimers[key] == nil, page.stillPath == nil else { return }
        let isFirstPage = page.id == reader.currentPage?.id && !isShown(page)
        let seconds = isFirstPage ? PaintDeadlines.firstPage : PaintDeadlines.pageBehind
        giveUpTimers[key] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.giveUp(on: key, because: "This picture is taking a while, so this page is one to imagine for now.")
        }
    }

    /// This page version's picture isn't coming (yet): it's ready without one.
    private func giveUp(on key: PageKey, because message: String) {
        guard let page = reader.page(id: key.id), page.version == key.version, page.stillPath == nil,
              (pictureStates[key] ?? .painting) == .painting else { return }
        pictureStates[key] = .gaveUp
        scriptLog?.append("page \(page.index + 1) shows without its picture")
        note(message)
        refreshReadiness()
    }

    /// The still is on disk: the page on screen can show; the page behind waits up to the
    /// motion grace for its motion prompt, so look again then.
    private func stillStored(_ key: PageKey) {
        pictureStates[key] = .stored
        stillStoredAt[key] = .now
        giveUpTimers[key]?.cancel()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(PaintDeadlines.motionGrace))
            self?.readinessTick += 1
            self?.refreshReadiness()
        }
        refreshReadiness()
    }

    /// A still that couldn't be stored counts as a failed picture: paint it once more, then give up.
    private func repaintAfterStoreFailure(_ page: PageContent) {
        let key = page.key
        guard !storeRepainted.contains(key), let pipeline = services.pipeline else {
            giveUp(on: key, because: "A picture didn't arrive, so this page is one to imagine for now.")
            return
        }
        storeRepainted.insert(key)
        scriptLog?.append("page \(page.index + 1): its picture didn't store, painting it again")
        paintTasks[page.id]?.task.cancel()
        paintTasks[page.id] = nil
        _ = callPipeline { await pipeline.cancelPaint(pageId: page.id) }
        paint(page)
    }

    /// A page behind replaced by a rewrite: its picture and motion states go with it.
    private func forgetReadiness(of page: PageContent) {
        giveUpTimers[page.key]?.cancel()
        giveUpTimers[page.key] = nil
        pictureStates[page.key] = nil
        motionStates[page.key] = nil
        stillStoredAt[page.key] = nil
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
        // The opening prompt was turned away (the note says why): back to the empty book.
        if outcome.page == nil, isOpening(build) { endOpening() }
        if let page = outcome.page {
            switch reader.place(page) {
            case let .onScreen(placed):
                paint(placed)
            case let .behind(placed, replaced):
                if let replaced {
                    forget(replaced)
                    forgetReadiness(of: replaced)
                }
                if build.direction != nil { rewrittenPageId = placed.id }
                // It paints once the page on screen shows (`ensureBuilds` then).
                if isShown(reader.currentPage) { paint(placed) }
                refreshLive()
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
                stillStored(key)
                prepareLayers(for: updated)
            }
        } catch {
            scriptLog?.append("still failed to store: \(error.localizedDescription)")
            repaintAfterStoreFailure(page)
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

    // MARK: - Living page

    private func pageChanged(to page: PageContent?) {
        // An empty book has nothing to change: page 1 waits for the opening prompt.
        guard let page, !page.text.isEmpty else {
            refreshLive()
            return
        }
        // Folded while a direction was re-building this page: the old page behind shows as it
        // was, and the direction applies to the new page behind instead.
        // Once its words have landed, the rebuilt page is what just showed, so the build only
        // finishes its picture (R-40).
        // A build stays in `builds` only until its words land, so this never re-applies a direction.
        if let build = builds[page.index], let direction = build.direction {
            scriptLog?.append("folded mid-rebuild: the direction moves to page \(page.index + 2)")
            drop(build)
            note("Your change will show on the next page.")
            runDirection(direction)
        }
        refreshWorking()
        ensureBuilds()
        // A page turned to was ready, so it shows now; page 1 shows once it's painted.
        if !isShown(page) { refreshReadiness() }
        refreshLive()
    }

    /// Tells the living page which page is on screen and which one the next fold opens, with
    /// their motion prompts; it animates, loops and pre-animates from there (`PreRollPlanner`).
    private func refreshLive() {
        // Only a page the parent may see comes alive ("no page until painted").
        let current = shownPage
        let next = current.flatMap { current in
            reader.book.pages.first { $0.index == current.index + 1 }
                ?? reader.pendingNext.flatMap { $0.index == current.index + 1 ? $0 : nil }
        }
        live.update(current: current.map(livePage), behind: next.map(livePage))
    }

    private func livePage(_ page: PageContent) -> LivePageController.LivePage {
        LivePageController.LivePage(page: page, prompt: motionPrompts[page.key])
    }

    /// Before saving: animate and record any page whose clip isn't complete yet (ROADMAP
    /// Phase 5), so the saved book replays every page. Pages without a picture or motion
    /// prompt keep their still. Each page waits at most `perPage`, and nothing waits past
    /// `deadline`: pages left over keep their still (IMP-13).
    func completeClips(perPage: Duration = .seconds(45), until deadline: ContinuousClock.Instant? = nil) async -> (recorded: Int, missing: Int) {
        var recorded = 0
        var missing = 0
        // A loop already being recorded or baked for the page on screen finishes first, rather
        // than being superseded by another page's recording.
        if let current = reader.currentPage {
            let waitUntil = min(ContinuousClock.now.advanced(by: perPage), deadline ?? .now.advanced(by: perPage))
            while ContinuousClock.now < waitUntil, live.isMakingLoop(for: current.key), reader.page(id: current.id)?.clipPath == nil {
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        for page in reader.book.pages where reader.page(id: page.id)?.clipPath == nil && !page.text.isEmpty && !live.isHeld(page) {
            let hasTime = deadline.map { ContinuousClock.now < $0 } ?? true
            guard hasTime, live.canAnimate, let prompt = motionPrompts[page.key], page.stillPath != nil else {
                missing += 1
                continue
            }
            // Recorded hidden (a clip nobody saw live must pass its frame checks to be kept).
            live.complete(LivePageController.LivePage(page: page, prompt: prompt))
            let pageDeadline = min(ContinuousClock.now.advanced(by: perPage), deadline ?? .now.advanced(by: perPage))
            while ContinuousClock.now < pageDeadline, reader.page(id: page.id)?.clipPath == nil,
                  !live.isSpent(page), !live.isHeld(page) {
                try? await Task.sleep(for: .milliseconds(500))
            }
            if reader.page(id: page.id)?.clipPath != nil { recorded += 1 } else { missing += 1 }
        }
        live.complete(nil)
        scriptLog?.append("completed clips: recorded \(recorded), still missing \(missing)")
        return (recorded, missing)
    }

    /// Adds a line to the scripted run's log (automation only).
    func record(_ line: String) {
        scriptLog?.append(line)
    }

    /// Attaches a page's baked loop only to the page version it was recorded from; a loop for
    /// a page rewritten (or dropped) meanwhile is deleted.
    private func attachClip(_ url: URL, to key: PageKey) {
        // A loop that lands after the book ended (and saved) would never be kept.
        let attached = hasEnded ? nil : reader.updatePage(id: key.id, version: key.version) { $0.with(clipPath: url.path(percentEncoded: false)) }
        if attached == nil {
            try? FileManager.default.removeItem(at: url)
            scriptLog?.append("loop for a replaced page dropped")
        }
        refreshLive()
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
