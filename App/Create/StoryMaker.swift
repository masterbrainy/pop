import Foundation
import Observation
import PopKit

/// Live, parent-driven creation along a story path (P-04): the brief plans a path that always
/// ends, the page on screen is written first, and the next page is fully built behind it
/// (words, picture, motion). A direction (speech or typing) re-plans from the page behind and
/// rebuilds it; the page on screen never changes. Folding shows the page behind, and the one
/// after it starts building. The engine never turns the page; the parent folds.
@MainActor
@Observable
final class StoryMaker {
    var speaker: Speaker = .parent
    private(set) var isWorking = false
    private(set) var isListening = false
    private(set) var partial = ""
    /// A gentle note for the parent (an unsafe request, a failure), shown briefly.
    private(set) var parentNote: String?
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
    /// One page being built: its words (a `path` or `page` call), then picture and motion.
    private struct Build {
        let id = UUID()
        let index: Int
        /// The direction this build follows, if it re-plans the path for one.
        let direction: StoryTurnInput?
    }

    /// The build in flight for each page index; events from a replaced build are ignored.
    @ObservationIgnored private var builds: [Int: Build] = [:]
    @ObservationIgnored private var buildTasks: [UUID: Task<Void, Never>] = [:]
    /// Pipeline calls go in order, so a newer build for a page always replaces an older one.
    @ObservationIgnored private var pipelineCalls: Task<Void, Never>?
    /// Serializes directions so a second one while one is in flight isn't lost (R-31).
    @ObservationIgnored private let turnQueue = TurnQueue()
    @ObservationIgnored private var directionInFlight = false
    /// Direction builds that already handed the queue on to the next direction.
    @ObservationIgnored private var handedOn: Set<UUID> = []
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
        live.onClip = { [weak self] pageId, url in self?.attachClip(url, to: pageId) }
        live.onFrameFlagged = { [weak self] pageId in
            guard let self else { return }
            // A clip saved before the flag must not replay in the finished book (R-38).
            if let page = self.reader.page(id: pageId), page.clipPath != nil {
                self.reader.updatePage(index: page.index) { $0.with(clipPath: nil) }
            }
            self.note("The moving picture drifted off, so this page keeps its still picture.")
        }
        reader.onPageChange = { [weak self] page in self?.pageChanged(to: page) }
    }

    var canCreate: Bool { services.server != nil }

    /// Warms the living page so the first picture animates quickly.
    func begin() async {
        guard let server = services.server else {
            note("Pop! is offline, so new pages can't be made right now. Saved books still work.")
            return
        }
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
        ensureBuilds()
        await playScriptedTurns()
    }

    /// Whether the page on screen is the story's ending: there's no page behind it, and
    /// closing the book finishes it.
    var isOnLastPage: Bool {
        guard let page = reader.currentPage, !page.text.isEmpty else { return false }
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
            reader.update(book: HeroCharacter.seeding(reader.book, drawing: drawing, referencePath: art.path))
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
        await stopListening()
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
        buildTasks.values.forEach { $0.cancel() }
        buildTasks = [:]
        builds = [:]
        await stopListening()
        await live.kill()
    }

    // MARK: - Input

    func submit(_ text: String, kind: InputKind = .typed) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        enqueue(StoryTurnInput(kind: kind, speaker: speaker, text: trimmed))
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

    private func startListening() async {
        let input: any SpeechInput
        if let server = services.server {
            input = RealtimeTranscriber {
                let token = try await server.sttToken()
                return RealtimeTranscriber.Secret(value: token.clientSecret, model: token.model)
            }
        } else {
            input = AppleTranscriber()
        }
        do {
            try await input.start()
        } catch {
            note(error.localizedDescription)
            return
        }
        speech = input
        isListening = true
        speechTask = Task { [weak self] in
            for await update in input.updates {
                guard let self else { return }
                switch update {
                case let .partial(text): self.partial = text
                case let .final(text):
                    self.partial = ""
                    self.submit(text, kind: .speech)
                case let .failed(message):
                    self.note(message)
                    await self.stopListening()
                }
            }
        }
    }

    private func stopListening() async {
        speechTask?.cancel()
        speechTask = nil
        await speech?.stop()
        speech = nil
        isListening = false
        partial = ""
    }

    // MARK: - Story path

    /// A direction re-plans the path from the page behind and rebuilds it. While the page on
    /// screen is still empty (the story is just starting), it shapes that page instead.
    private func runDirection(_ input: StoryTurnInput) {
        guard services.pipeline != nil, let current = reader.currentPage else {
            note("Pop! is offline, so new pages can't be made right now.")
            finishDirection()
            return
        }
        if isOnLastPage {
            note("This is the last page. Close the book to finish the story.")
            finishDirection()
            return
        }
        startBuild(at: current.text.isEmpty ? current.index : current.index + 1, direction: input)
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

    /// Starts whatever the page on screen and the page behind still need: words for an empty
    /// page, the next page behind, or a picture that never arrived.
    private func ensureBuilds() {
        guard services.pipeline != nil, let current = reader.currentPage else { return }
        let bible = reader.book.bible
        if current.text.isEmpty {
            if builds[current.index] == nil { startBuild(at: current.index, direction: nil) }
            return
        }
        if current.stillPath == nil, builds[current.index] == nil { startPicture(for: current) }
        let behind = current.index + 1
        guard bible.hasPage(after: current.index), builds[behind] == nil else { return }
        if let pending = reader.pendingNext, pending.index == behind {
            if pending.stillPath == nil { startPicture(for: pending) }
        } else {
            startBuild(at: behind, direction: nil)
        }
    }

    /// Writes page `index` (a `path` call to plan or follow a direction, else a `page` call
    /// along the path), then paints it and prepares its motion.
    private func startBuild(at index: Int, direction: StoryTurnInput?) {
        guard let pipeline = services.pipeline else { return }
        let book = reader.book
        let shown = book.pages.filter { $0.index < index && !$0.text.isEmpty }
        let request = direction != nil || index >= book.bible.path.count
            ? StoryEngine.pathRequest(book: book, kid: kid, settings: settings, shownPages: shown, index: index, input: direction)
            : StoryEngine.pageRequest(book: book, kid: kid, settings: settings, shownPages: shown, index: index)
        scriptLog?.append("building page \(index + 1) · \(request.mode.rawValue)\(direction == nil ? "" : " for a direction")")
        run(Build(index: index, direction: direction)) { await pipeline.buildPage(request, book: book) }
    }

    /// Paints a page whose words are already known (its earlier build was replaced or failed).
    private func startPicture(for page: PageContent) {
        guard let pipeline = services.pipeline else { return }
        let book = reader.book
        run(Build(index: page.index, direction: nil)) { await pipeline.preparePendingDraft(page, book: book) }
    }

    private func run(_ build: Build, _ start: @escaping @Sendable () async -> AsyncStream<PagePipelineEvent>) {
        builds[build.index] = build
        refreshWorking()
        let previous = pipelineCalls
        let started = Task { () -> AsyncStream<PagePipelineEvent> in
            await previous?.value
            return await start()
        }
        pipelineCalls = Task { _ = await started.value }
        buildTasks[build.id] = Task { [weak self] in
            for await event in await started.value {
                await self?.apply(event, from: build)
            }
            self?.ended(build)
        }
    }

    private func ended(_ build: Build) {
        buildTasks[build.id] = nil
        guard builds[build.index]?.id == build.id else { return }
        builds[build.index] = nil
        if build.direction != nil, handedOn.insert(build.id).inserted { finishDirection() }
        refreshWorking()
        Task { [weak self] in
            guard let self, let pipeline = self.services.pipeline else { return }
            self.latency = await pipeline.latencyTable()
        }
    }

    /// Stops a build (its page was shown before it finished re-planning).
    private func drop(_ build: Build) {
        builds[build.index] = nil
        buildTasks[build.id]?.cancel()
        buildTasks[build.id] = nil
        if let pipeline = services.pipeline {
            let previous = pipelineCalls
            pipelineCalls = Task {
                await previous?.value
                await pipeline.cancel(pageIndex: build.index)
            }
        }
    }

    private func refreshWorking() {
        let writingCurrent = reader.currentPage.map { $0.text.isEmpty && builds[$0.index] != nil } ?? false
        isWorking = directionInFlight || writingCurrent
    }

    private func apply(_ event: PagePipelineEvent, from build: Build) async {
        guard builds[build.index]?.id == build.id else { return }
        switch event {
        case let .pageWritten(outcome):
            written(outcome, by: build)
        case let .stillReady(pageIndex, path, url):
            makeReferences(fromStill: path)
            await storeStill(url: url, pageIndex: pageIndex)
        case let .motionReady(pageIndex, prompt):
            if let page = pageWith(index: pageIndex) {
                motionPrompts[page.id] = prompt
                if page.id == reader.currentPage?.id { animate(page) }
            }
        case let .failed(message):
            let lines = message.split(separator: "\n", maxSplits: 1).map(String.init)
            if lines.count > 1 { scriptLog?.append("failure detail: \(lines[1])") }
            note(lines.first ?? message)
        case .textReady:
            break
        }
    }

    /// A page's words arrived: an empty page on screen takes them, otherwise they become the
    /// page behind. A page the reader has already seen is never changed.
    private func written(_ outcome: PathOutcome, by build: Build) {
        // Take only the bible: pages may have gained pictures since the request went out.
        reader.update(book: reader.book.with(bible: outcome.book.bible.carryingReferences(from: reader.book.bible)))
        if let message = outcome.parentNote { note(message) }
        if let page = outcome.page {
            if let shown = reader.book.pages.first(where: { $0.index == page.index }) {
                if shown.text.isEmpty { reader.replace(page) }
            } else if page.index == (reader.currentPage?.index ?? -2) + 1 {
                reader.pendingNext = page
            }
            scriptLog?.append("page \(page.index + 1)/\(reader.book.bible.path.count) written\(build.direction == nil ? "" : " for a direction")")
        }
        // The next direction can go as soon as these words land; the picture keeps going.
        if build.direction != nil, handedOn.insert(build.id).inserted { finishDirection() }
        refreshWorking()
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
                    self.reader.update(book: self.reader.book.with(bible: self.reader.book.bible.settingReference(art.path, for: character.id)))
                    self.scriptLog?.append("reference ready for \(character.id) in \(art.ms) ms")
                } catch {
                    self?.scriptLog?.append("reference failed for \(character.id): \(error.localizedDescription)")
                    self?.referencesRequested.remove(character.id)
                }
            }
        }
    }

    private func storeStill(url: String, pageIndex: Int) async {
        guard let remote = URL(string: url), let page = pageWith(index: pageIndex) else { return }
        do {
            // Named by page id too: a rebuilt page behind reuses its index and version.
            let path = try await services.media.store(from: remote, named: "\(reader.book.id)-p\(pageIndex)-\(page.id.uuidString.prefix(8))-v\(page.version).png")
            reader.updatePage(index: pageIndex) { $0.with(stillPath: path) }
            if let updated = pageWith(index: pageIndex) { prepareLayers(for: updated) }
        } catch {
            note("A picture didn't arrive. It will be tried again on the next turn.")
        }
    }

    /// Pop-up layers for a page with a picture, made in the background (Phase 4).
    private func prepareLayers(for page: PageContent) {
        guard let server = services.server else { return }
        layerTasks[page.id]?.cancel()
        let book = reader.book
        let media = services.media
        layerTasks[page.id] = Task { [weak self] in
            do {
                let layers = try await LayerMaker.makeLayers(for: page, book: book, server: server, media: media)
                guard !Task.isCancelled, let self else { return }
                // Only if the page is still the one (and version) these layers were drawn for.
                guard let now = self.pageWith(index: page.index), now.id == page.id, now.version == page.version else { return }
                self.reader.updatePage(index: page.index) { $0.with(layers: layers) }
                self.scriptLog?.append("layers ready for page \(page.index + 1): \(layers.cutouts.count) cutouts")
            } catch {
                self?.scriptLog?.append("layers failed for page \(page.index + 1): \(error.localizedDescription)")
            }
        }
    }

    private func pageWith(index: Int) -> PageContent? {
        reader.book.pages.first { $0.index == index } ?? (reader.pendingNext?.index == index ? reader.pendingNext : nil)
    }

    // MARK: - Living page

    private func pageChanged(to page: PageContent?) {
        Task { await live.pageWillChange() }
        guard let page else { return }
        // Folded while a direction was re-building this page: the old page behind shows as it
        // was, and the direction applies to the new page behind instead.
        if !page.text.isEmpty, let build = builds[page.index], let direction = build.direction {
            scriptLog?.append("folded mid-rebuild: the direction moves to page \(page.index + 2)")
            drop(build)
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
    /// prompt keep their still. Each page waits at most `perPage`.
    func completeClips(perPage: Duration = .seconds(45)) async -> (recorded: Int, missing: Int) {
        var recorded = 0
        var missing = 0
        for page in reader.book.pages where page.clipPath == nil && !page.text.isEmpty && !live.isHeld(page) {
            guard live.canAnimate, let prompt = motionPrompts[page.id], let data = StillImageLoader.data(for: page.stillPath) else {
                missing += 1
                continue
            }
            await live.pageWillChange()
            await live.show(page, still: data, prompt: prompt)
            let deadline = ContinuousClock.now.advanced(by: perPage)
            while ContinuousClock.now < deadline, reader.page(id: page.id)?.clipPath == nil {
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
        guard let page = reader.page(id: pageId) else { return }
        reader.updatePage(index: page.index) { $0.with(clipPath: url.path(percentEncoded: false)) }
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
