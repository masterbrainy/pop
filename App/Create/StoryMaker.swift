import Foundation
import Observation
import PopKit

/// Live, parent-driven creation (ROADMAP Phase 2): speech or typing becomes a story turn,
/// the page pipeline fills the page with words, then a picture, then a motion prompt, and
/// the living page animates it (Phase 3). The engine never turns the page; the parent folds.
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
    @ObservationIgnored private var turnTask: Task<Void, Never>?
    /// Serializes turns so a second input while one is in flight isn't lost (R-31).
    @ObservationIgnored private let turnQueue = TurnQueue()
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
        live.onFrameFlagged = { [weak self] _ in
            self?.note("The moving picture drifted off, so this page keeps its still picture.")
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
        if let heroDrawing {
            await seedHero(heroDrawing, server: server)
        }
        await playScriptedTurns()
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
        let log = FileLog(name: "story")
        scriptLog = log
        let started = Date()
        for turn in LaunchOptions.storyTurns {
            switch turn.lowercased() {
            case "fold": reader.turnForward()
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
            case "you continue": continueStory()
            default: submit(turn)
            }
            try? await Task.sleep(for: .milliseconds(300))
            while isWorking { try? await Task.sleep(for: .milliseconds(250)) }
            AppLog.scene.info("scripted turn done · page \(self.reader.pageNumber)")
            let page = reader.currentPage
            log.append("turn '\(turn)' → page \(reader.pageNumber) still=\(page?.stillPath != nil) motion=\(page.map { motionPrompts[$0.id] != nil } ?? false) pending=\(reader.pendingNext != nil): \(page?.text ?? "")")
        }
        log.append("done in \(Int(Date().timeIntervalSince(started))) s · pages \(reader.book.pages.count) · live \(live.status) · latency \(String(describing: latency))")
        if let note = parentNote { log.append("note: \(note)") }
        // Give the last page time to go live and record its clip, then end the paid session.
        try? await Task.sleep(for: .seconds(40))
        log.append("before end: live \(live.status) · clip \(reader.currentPage?.clipPath != nil) · credits $\(String(format: "%.2f", live.credits))")
        await end()
        log.append("ended")
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
        turnTask?.cancel()
        await stopListening()
        await live.kill()
    }

    // MARK: - Input

    func submit(_ text: String, kind: InputKind = .typed) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        enqueue(StoryTurnInput(kind: kind, speaker: speaker, text: trimmed))
    }

    func continueStory() {
        enqueue(StoryEngine.continueInput(speaker: speaker))
    }

    /// Routes an input through `turnQueue` (R-31): starts a turn immediately if
    /// none is in flight, else queues it to be merged in when the current one
    /// returns. `isWorking` stays true until the queue fully drains.
    private func enqueue(_ input: StoryTurnInput) {
        isWorking = true
        Task { [weak self] in
            guard let self, let toRun = await self.turnQueue.submit(input) else { return }
            self.runTurn(toRun)
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

    // MARK: - Pipeline

    private func runTurn(_ input: StoryTurnInput) {
        guard let pipeline = services.pipeline, let draft = reader.currentPage else {
            note("Pop! is offline, so new pages can't be made right now.")
            isWorking = false
            Task { [weak self] in await self?.turnQueue.reset() }
            return
        }
        isWorking = true
        turnTask = Task { [weak self] in
            guard let self else { return }
            let events = await pipeline.run(book: reader.book, kid: kid, settings: settings, currentDraft: draft, input: input)
            for await event in events {
                await self.apply(event)
            }
            self.latency = await pipeline.latencyTable()
            // Anything that arrived while this turn ran is queued; run it next,
            // joined into one input. `isWorking` stays true until the queue drains.
            if let next = await self.turnQueue.drain() {
                self.runTurn(next)
            } else {
                self.isWorking = false
            }
        }
    }

    private func apply(_ event: PagePipelineEvent) async {
        switch event {
        case let .textReady(outcome):
            // A reference sheet can land while a turn is in flight; keep it.
            reader.update(book: outcome.book.with(bible: outcome.book.bible.carryingReferences(from: reader.book.bible)))
            reader.replace(outcome.currentDraft)
            if let pending = outcome.pendingNextDraft { reader.pendingNext = pending }
            if let message = outcome.parentNote { note(message) }
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
        }
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
            let path = try await services.media.store(from: remote, named: "\(reader.book.id)-p\(pageIndex)-v\(page.version).png")
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
                // Only if the page is still the version these layers were drawn for.
                guard self.pageWith(index: page.index)?.version == page.version else { return }
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
