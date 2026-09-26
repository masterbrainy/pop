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
    @ObservationIgnored private var motionPrompts: [UUID: String] = [:]
    @ObservationIgnored private var speech: (any SpeechInput)?
    @ObservationIgnored private var speechTask: Task<Void, Never>?
    @ObservationIgnored private var turnTask: Task<Void, Never>?
    @ObservationIgnored private var noteTask: Task<Void, Never>?

    init(reader: BookReader, kid: KidProfile, settings: ParentSettings, services: AppServices = .shared) {
        self.reader = reader
        self.kid = kid
        self.settings = settings
        self.services = services
        live.onClip = { [weak self] pageId, url in self?.attachClip(url, to: pageId) }
        reader.onPageChange = { [weak self] page in self?.pageChanged(to: page) }
    }

    var canCreate: Bool { services.server != nil }

    /// Warms the living page so the first picture animates quickly.
    func begin() async {
        guard let server = services.server else {
            note("Pop! is offline, so new pages can't be made right now. Saved books still work.")
            return
        }
        await live.warmUp(server: server)
        pageChanged(to: reader.currentPage)
        await playScriptedTurns()
    }

    /// Plays `-storyTurns` for automated end-to-end checks, waiting for each turn to finish.
    private func playScriptedTurns() async {
        guard !LaunchOptions.storyTurns.isEmpty else { return }
        let log = FileLog(name: "story")
        let started = Date()
        for turn in LaunchOptions.storyTurns {
            switch turn.lowercased() {
            case "fold": reader.turnForward()
            case "you continue": continueStory()
            default: submit(turn)
            }
            try? await Task.sleep(for: .milliseconds(300))
            while isWorking { try? await Task.sleep(for: .milliseconds(250)) }
            AppLog.scene.info("scripted turn done: \(turn, privacy: .public) · page \(self.reader.pageNumber) · \(self.reader.currentPage?.text ?? "", privacy: .public)")
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

    func end() async {
        turnTask?.cancel()
        await stopListening()
        await live.kill()
    }

    // MARK: - Input

    func submit(_ text: String, kind: InputKind = .typed) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        runTurn(StoryTurnInput(kind: kind, speaker: speaker, text: trimmed))
    }

    func continueStory() {
        runTurn(StoryEngine.continueInput(speaker: speaker))
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
            return
        }
        isWorking = true
        turnTask = Task { [weak self] in
            guard let self else { return }
            let events = await pipeline.run(book: reader.book, kid: kid, settings: settings, currentDraft: draft, input: input)
            for await event in events {
                await self.apply(event)
            }
            self.isWorking = false
            self.latency = await pipeline.latencyTable()
        }
    }

    private func apply(_ event: PagePipelineEvent) async {
        switch event {
        case let .textReady(outcome):
            reader.update(book: outcome.book)
            reader.replace(outcome.currentDraft)
            if let pending = outcome.pendingNextDraft { reader.pendingNext = pending }
            if let message = outcome.parentNote { note(message) }
        case let .stillReady(pageIndex, _, url):
            await storeStill(url: url, pageIndex: pageIndex)
        case let .motionReady(pageIndex, prompt):
            if let page = pageWith(index: pageIndex) {
                motionPrompts[page.id] = prompt
                if page.id == reader.currentPage?.id { animate(page) }
            }
        case let .failed(message):
            note(message)
        }
    }

    private func storeStill(url: String, pageIndex: Int) async {
        guard let remote = URL(string: url), let page = pageWith(index: pageIndex) else { return }
        do {
            let path = try await services.media.store(from: remote, named: "\(reader.book.id)-p\(pageIndex)-v\(page.version).png")
            reader.updatePage(index: pageIndex) { $0.with(stillPath: path) }
        } catch {
            note("A picture didn't arrive. It will be tried again on the next turn.")
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

    private func attachClip(_ url: URL, to pageId: UUID) {
        guard let page = reader.page(id: pageId) else { return }
        reader.updatePage(index: page.index) { $0.with(clipPath: url.path(percentEncoded: false)) }
    }

    private func note(_ message: String) {
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
