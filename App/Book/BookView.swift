import PopKit
import SwiftUI

/// A book on the Duo: the spread while open, the cover while closed. Folding turns and pops
/// pages through `HingeModel`. While creating, the story controls sit under the text page,
/// and keeping the phone closed (or tapping Finish) ends the book (PRD H3, Phase 5).
struct BookView: View {
    let kid: KidProfile
    var onClose: () -> Void = {}
    var onFinish: (Book) -> Void = { _ in }

    @State private var hinge = HingeModel()
    @State private var reader: BookReader
    @State private var maker: StoryMaker?
    @State private var readAloud = ReadAloud()
    @State private var showsDebugPanel = LaunchOptions.debugHinge
    @State private var finishing = false

    init(book: Book, kid: KidProfile, settings: ParentSettings = ParentSettings(), mode: BookMode, heroDrawing: HeroDrawing? = nil,
         onClose: @escaping () -> Void = {}, onFinish: @escaping (Book) -> Void = { _ in }) {
        self.kid = kid
        self.onClose = onClose
        self.onFinish = onFinish
        let reader = BookReader(book: book, mode: mode)
        _reader = State(initialValue: reader)
        _maker = State(initialValue: mode == .creating ? StoryMaker(reader: reader, kid: kid, settings: settings, heroDrawing: heroDrawing) : nil)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            content
            if showsDebugPanel {
                VStack(spacing: 8) {
                    if let maker {
                        SceneDebugOverlay(live: maker.live, latency: maker.latency)
                    }
                    DebugHingePanel(hinge: hinge)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, maker == nil ? 20 : 84)
            }
        }
        .overlay(alignment: .top) { banner }
        .overlay(alignment: .topLeading) { if hinge.state.phase != .closed { topBar } }
        .readsHinge(into: hinge)
        .onTapGesture(count: 3) { showsDebugPanel.toggle() }
        .onChange(of: hinge.state.popDepth) { _, depth in reader.setPopDepth(depth) }
        .task { await start() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            guard let maker, !finishing else { return }
            Task { await maker.pauseLive() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            guard let maker, !finishing else { return }
            Task { await maker.resumeLive() }
        }
        .onDisappear {
            readAloud.stop()
            if let maker { Task { await maker.end() } }
        }
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden()
    }

    @ViewBuilder private var content: some View {
        if hinge.state.phase == .closed {
            CoverView(book: reader.book, kid: kid)
        } else if let maker {
            SpreadView(page: reader.currentPage, pageNumber: reader.pageNumber, level: kid.readingLevel,
                       curl: hinge.state.curl, popDepth: reader.popDepth, live: maker.live)
                .overlay(alignment: .bottom) {
                    StoryInputBar(
                        speaker: Binding(get: { maker.speaker }, set: { maker.speaker = $0 }),
                        isListening: maker.isListening, partial: maker.partial, isWorking: maker.isWorking,
                        onToggleMic: { Task { await maker.toggleMic() } },
                        onSubmit: { maker.submit($0) },
                        onContinue: { maker.continueStory() }
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 14)
                }
        } else {
            SpreadView(page: reader.currentPage, pageNumber: reader.pageNumber, level: kid.readingLevel,
                       curl: hinge.state.curl, popDepth: reader.popDepth, replaysClips: true,
                       highlight: readAloud.spokenRange)
        }
    }

    @ViewBuilder private var banner: some View {
        VStack(spacing: 8) {
            if let note = maker?.parentNote {
                Label(note, systemImage: "heart.text.square")
                    .font(.callout)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: .capsule)
            }
            if reader.pendingNext != nil, hinge.state.phase != .closed {
                Label("Page full. Fold to turn", systemImage: "book.pages")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Theme.accent, in: .capsule)
            }
        }
        .padding(.top, 24)
        .animation(.easeInOut, value: maker?.parentNote)
        .animation(.easeInOut, value: reader.pendingNext?.id)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button(action: close) {
                Image(systemName: "xmark").font(.headline).padding(12).background(.ultraThinMaterial, in: .circle)
            }
            .accessibilityLabel("Back to the bookshelf")
            if maker != nil {
                Button(action: { Task { await finish() } }) {
                    Label(finishing ? "Finishing…" : "Finish", systemImage: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: .capsule)
                }
                .disabled(finishing || reader.book.pages.allSatisfy { $0.text.isEmpty })
            } else {
                Button(action: toggleReading) {
                    Image(systemName: readAloud.isReading ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.headline).padding(12).background(.ultraThinMaterial, in: .circle)
                }
                .accessibilityLabel(readAloud.isReading ? "Stop reading aloud" : "Read this page aloud")
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(20)
    }

    private func start() async {
        hinge.onEvent = { [reader] event in reader.handle(event) }
        reader.onClosedHold = { Task { await finishIfCreating() } }
        if maker == nil {
            reader.onPageChange = { page in
                guard ParentPreferences.readAlong, let page else { return }
                readAloud.read(page.text)
            }
        }
        hinge.start(script: LaunchOptions.hingeScript)
        maker?.onScriptedFinish = { await finish() }
        maker?.onScriptedPop = {
            hinge.play([.pop], interval: .milliseconds(80))
            try? await Task.sleep(for: .seconds(6))
        }
        await maker?.begin()
    }

    private func toggleReading() {
        if readAloud.isReading { readAloud.stop() } else { readAloud.read(reader.currentPage?.text ?? "") }
    }

    private func finishIfCreating() async {
        guard maker != nil, !finishing, reader.book.pages.contains(where: { !$0.text.isEmpty }) else { return }
        await finish()
    }

    /// Ends the book: a title from the story engine, the first picture as the cover, then save.
    private func finish() async {
        guard let maker, !finishing else { return }
        finishing = true
        _ = await maker.completeClips()
        await maker.end()
        let title = await BookFinisher.title(for: reader.book, kid: kid, settings: maker.settings)
        let firstStill = reader.book.pages.first(where: { $0.stillPath != nil })?.stillPath
        let cover = await BookFinisher.coverArt(for: reader.book, title: title, log: maker.record) ?? firstStill
        reader.finish(title: title, coverPath: cover)
        onFinish(reader.book)
        finishing = false
    }

    private func close() {
        if maker != nil, reader.book.pages.contains(where: { !$0.text.isEmpty }), reader.book.status == .draft {
            onFinish(reader.book)
        }
        onClose()
    }
}

/// Asks the story engine for a title; falls back to the book's first words.
@MainActor
enum BookFinisher {
    static func title(for book: Book, kid: KidProfile, settings: ParentSettings) async -> String {
        if let server = AppServices.shared.server {
            let request = StoryEngine.titleRequest(book: book, kid: kid, settings: settings)
            if let response = try? await server.storyTitle(request), !response.title.isEmpty { return response.title }
        }
        if let title = book.bible.title, !title.isEmpty { return title }
        let words = (book.pages.first?.text ?? "A new story").split(separator: " ").prefix(5).joined(separator: " ")
        return words.isEmpty ? "A new story" : words
    }

    /// Paints the cover (2:3, no lettering; the title is drawn over it) from the story's
    /// characters and its first page. Nil if it can't, and the first page's picture is used.
    static func coverArt(for book: Book, title: String, log: (String) -> Void = { _ in }) async -> String? {
        guard let server = AppServices.shared.server else { return nil }
        let media = AppServices.shared.media
        let opening = book.pages.first.map { $0.artPrompt ?? $0.text } ?? ""
        let prompt = "Cover art for a picture book about: \(title). The main characters together, inviting and joyful. Opening scene: \(opening). No words, letters or title anywhere in the picture; leave calm sky or space at the top for the title."
        let request = ArtRequest(bookId: book.id, kind: .cover, version: 1, prompt: prompt, characters: book.bible.characters)
        do {
            let art = try await server.art(request)
            guard !art.placeholder, let url = URL(string: art.url) else {
                log("cover art: placeholder returned")
                return nil
            }
            let path = try await media.store(from: url, named: "\(book.id)-cover.png")
            log("cover art ready in \(art.ms) ms")
            return path
        } catch {
            log("cover art failed: \(error.localizedDescription)")
            AppLog.story.error("cover art failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
