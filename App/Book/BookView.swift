import PopKit
import SwiftUI

/// A book on the Duo: the spread while open, the cover while closed. A page turns only when the
/// Duo folds to 80° or below and opens again, or from the corner arrow; folding to about 90°
/// pops the page up (`PostureConfig.closeToTurn`). While creating, the story controls sit under
/// the text page, and only Finish ends the book, so a slow close never finishes it by accident.
struct BookView: View {
    let kid: KidProfile
    var onClose: () -> Void = {}
    var onFinish: (Book) -> Void = { _ in }

    @State private var hinge = HingeModel(config: .closeToTurn)
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
        .overlay(alignment: .topLeading) { if !showsCover { topBar } }
        .overlay(alignment: .topTrailing) { if !showsCover { nextPageButton } }
        .readsHinge(into: hinge)
        .onTapGesture(count: 3) { showsDebugPanel.toggle() }
        // While making a book, each page is read aloud once its words are in and it's showing.
        .onChange(of: pageToReadAloud) { _, key in
            if key != nil, let text = reader.currentPage?.text {
                readAloud.read(text)
            } else if isCreating {
                readAloud.stop()
            }
        }
        // Each page's voice is fetched as soon as its words exist, so reading starts at once.
        .onChange(of: textsToPrepare, initial: true) { _, texts in
            texts.forEach(readAloud.prepare)
        }
        .onChange(of: readAloud.isReading) { _, reading in
            guard let maker, isCreating else { return }
            Task { await maker.setReadingAloud(reading) }
        }
        // On a Duo, angled is for talking into the story; open flat (to read) or closed isn't.
        .onChange(of: hinge.hasReadings && hinge.isAngled, initial: true) { _, angled in
            guard hinge.hasReadings, isCreating, !finishing, let maker else { return }
            Task { await maker.setListeningByPosture(angled) }
        }
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
        if showsCover {
            CoverView(book: reader.book, kid: kid)
        } else if let maker, reader.book.status == .draft {
            SpreadView(page: reader.currentPage, pageNumber: reader.pageNumber, level: kid.readingLevel,
                       curl: hinge.state.curl, popDepth: reader.popDepth, live: maker.live,
                       highlight: readAloud.spokenRange,
                       pictureUnavailable: reader.currentPage.map {
                           maker.unavailablePictures.contains($0.id) || maker.picturelessPages.contains($0.id)
                       } ?? false) {
                if !maker.hasBegun {
                    StoryStartPanel(ideas: maker.openingIdeas,
                                    onRemove: { maker.removeOpeningIdea(at: $0) },
                                    onBegin: { Task { await maker.beginStory() } })
                        .padding(.bottom, 70)
                }
            }
                .overlay {
                    // After Begin, until the first page is alive. The input bar stays usable on
                    // top, so the story can still be steered while it loads.
                    if let stage = maker.openingStage {
                        OpeningLoadingView(stage: stage, idea: maker.openingIdea)
                            .transition(.opacity)
                    }
                }
                .animation(.smooth, value: maker.openingStage)
                .onChange(of: maker.openingStage) { old, new in
                    if old != nil, new == nil { maker.openingShown() }
                }
                .overlay(alignment: .bottom) {
                    StoryInputBar(
                        isListening: maker.isListening, listensByPosture: hinge.hasReadings,
                        partial: maker.partial, isWorking: maker.isWorking,
                        onToggleMic: { Task { await maker.toggleMic() } },
                        onSubmit: { maker.submit($0) }
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

    /// The phone is shut, or opening again after a close: the cover shows until the next page
    /// replaces it (see `HingeModel.showsCover`).
    private var showsCover: Bool { hinge.showsCover }

    /// While making a book: the page (and version) to read aloud, once its words are in, it's
    /// on screen, and the first page's loading screen is gone. Nil while nothing should be read.
    private var pageToReadAloud: String? {
        guard isCreating, ParentPreferences.readAlong, !showsCover, maker?.openingStage == nil,
              let page = reader.currentPage, !page.text.isEmpty else { return nil }
        return "\(page.id)#\(page.version)"
    }

    /// The page on screen and the next ones (built ahead while making, or the book's next page
    /// while reading), whose voice to fetch ahead.
    private var textsToPrepare: [String] {
        guard ParentPreferences.readAlong else { return [] }
        let index = reader.pageNumber - 1
        let upcoming = isCreating ? reader.ahead : Array(reader.book.pages.dropFirst(index + 1).prefix(1))
        return ([reader.currentPage].compactMap { $0 } + upcoming).map(\.text).filter { !$0.isEmpty }
    }

    /// Making the book (not reading a finished one): only then do the story banners show.
    private var isCreating: Bool { maker != nil && reader.book.status == .draft }

    @ViewBuilder private var banner: some View {
        VStack(spacing: 8) {
            if let note = maker?.parentNote {
                Label(note, systemImage: "heart.text.square")
                    .font(.callout)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: .capsule)
            }
            if isCreating, maker?.isOnLastPage == true, !showsCover {
                Label("The end. Tap Finish to save the book", systemImage: "book.closed")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Theme.accent, in: .capsule)
            } else if isCreating, !showsCover, let status = maker?.nextPageStatus {
                nextPageBanner(status)
            }
        }
        .padding(.top, 24)
        .animation(.easeInOut, value: maker?.parentNote)
        .animation(.easeInOut, value: maker?.nextPageStatus)
    }

    /// Says a direction was heard while it re-writes the page behind, then that the page is ready.
    @ViewBuilder private func nextPageBanner(_ status: NextPageStatus) -> some View {
        switch status {
        case let .rewriting(direction, _):
            Label {
                Text("Rewriting the next page: “\(direction)”").lineLimit(2)
            } icon: {
                ProgressView().controlSize(.small).tint(.white)
            }
            .modifier(NextPageBannerStyle())
        case let .ready(rewritten):
            Label(rewritten ? "Next page rewritten · fold shut and open, or tap ›"
                            : "Next page ready · fold shut and open, or tap ›",
                  systemImage: rewritten ? "sparkles" : "book.pages")
                .modifier(NextPageBannerStyle())
        case .painting:
            Label {
                Text("Painting the next page…")
            } icon: {
                ProgressView().controlSize(.small).tint(.white)
            }
            .modifier(NextPageBannerStyle())
        case .none, .writing:
            EmptyView()
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button(action: close) {
                Image(systemName: "xmark").font(.headline).padding(12).background(.ultraThinMaterial, in: .circle)
            }
            .accessibilityLabel("Back to the bookshelf")
            if maker != nil, reader.book.status == .draft {
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

    /// The corner arrow: turns to the next page, the same as folding the Duo shut and opening it.
    /// While creating it waits (a spinner) until the page behind has its words and picture, and pulses while
    /// a direction re-writes it (turning then shows the page behind as it was, PRD S7).
    @ViewBuilder private var nextPageButton: some View {
        let creating = maker != nil && reader.book.status == .draft
        let hasNext = creating ? maker?.isOnLastPage == false && maker?.hasBegun == true : reader.pageNumber < reader.book.pages.count
        if hasNext {
            let status = creating ? maker?.nextPageStatus : nil
            let ready = creating ? status?.canTurn == true : true
            let rewriting = if case .rewriting = status { true } else { false }
            Button(action: { reader.turnForward() }) {
                ZStack {
                    if ready {
                        Image(systemName: "chevron.right").font(.headline)
                            .symbolEffect(.pulse, isActive: rewriting)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: .circle)
            }
            .foregroundStyle(Theme.ink)
            .padding(20)
            .accessibilityLabel(status == .painting ? "The next page is still being painted"
                                : !ready ? "The next page is still being written"
                                : rewriting ? "Next page, as it was before your change" : "Next page")
        }
    }

    private func start() async {
        hinge.onEvent = { [reader] event in reader.handle(event) }
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

    /// How long Finish may take at most. Pages whose clip isn't recorded by then keep their
    /// still; a title or cover not ready by then falls back to the first words and first picture.
    private static let finishBudget: Duration = .seconds(20)

    /// Ends the book (IMP-13): the title and cover start at once and run while missing clips
    /// are recorded, everything stops at `finishBudget`, then the book saves.
    private func finish() async {
        guard let maker, !finishing else { return }
        finishing = true
        let deadline = ContinuousClock.now.advanced(by: Self.finishBudget)
        let book = reader.book
        let settings = maker.settings
        let titleTask = Task { await BookFinisher.title(for: book, kid: kid, settings: settings) }
        let coverTask = Task { await BookFinisher.coverArt(for: book, title: await titleTask.value, log: maker.record) }

        let clips = await maker.completeClips(until: deadline)
        await maker.end()
        let title = await TaskDeadline.value(of: titleTask, until: deadline) ?? BookFinisher.fallbackTitle(for: book)
        let firstStill = reader.book.pages.first(where: { $0.stillPath != nil })?.stillPath
        let cover = await TaskDeadline.value(of: coverTask, until: deadline) ?? nil
        maker.record("finished in \(Int((Self.finishBudget - (deadline - .now)) / .seconds(1))) s · clips recorded \(clips.recorded), stills kept \(clips.missing) · cover \(cover == nil ? "first picture" : "painted")")
        reader.finish(title: title, coverPath: cover ?? firstStill)
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

/// The accent capsule the next-page banner uses.
private struct NextPageBannerStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Theme.accent, in: .capsule)
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
        return fallbackTitle(for: book)
    }

    /// The story's own title if it has one, else its first few words.
    static func fallbackTitle(for book: Book) -> String {
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
