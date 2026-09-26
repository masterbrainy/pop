import PencilKit
import PopKit
import SwiftUI

/// The guided setup (IMP-24): four picture cards (who's the hero, where, what goes wrong, how
/// it should feel) that anyone can answer by tapping or speaking, with "Surprise me" on each and
/// "Just start" always there. The cards are read aloud with the on-device voice when "Child is
/// here" is on. An optional "what's it for" chip opens the real-moment and teach fields. The kid
/// profile's interests only show up as suggested tiles; they're never sent as the book's interests.
struct SetupCardsView: View {
    let kid: KidProfile
    let onStart: (StoryBrief, HeroDrawing?) -> Void

    @State private var step = 0
    @State private var answers: [SetupCard: BriefAnswer] = [:]
    @State private var mood: StoryMood?
    @State private var purpose: StoryPurpose?
    @State private var realMoment = ""
    @State private var teach = ""
    @State private var childIsHere = false
    @State private var readAloud = ReadAloud()
    @State private var listener = CardListener()
    @State private var note: String?
    @State private var wantsHeroDrawing = false
    @State private var canvasView = PKCanvasView()
    @State private var crayonColor: Color = .red
    @State private var heroDescription = ""

    private static let moodStep = SetupCard.allCases.count

    var body: some View {
        VStack(spacing: 0) {
            purposeChips
            TabView(selection: $step) {
                ForEach(Array(SetupCard.allCases.enumerated()), id: \.offset) { index, card in
                    tilePage(card).tag(index)
                }
                moodPage.tag(Self.moodStep)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            if let note {
                Text(note).font(.footnote).foregroundStyle(Theme.accent).padding(.horizontal, 24)
            }
            startButtons
        }
        .background(Theme.paper)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Toggle(isOn: $childIsHere) { Label("Child is here", systemImage: "figure.and.child.holdinghands") }
                    .toggleStyle(.button)
                    .accessibilityHint("Reads each card aloud")
            }
        }
        .onChange(of: step) { _, _ in
            Task { await listener.stop() }
            if childIsHere { speakPrompt() }
        }
        .onChange(of: childIsHere) { _, isHere in
            if isHere { speakPrompt() } else { readAloud.stop() }
        }
        .onDisappear {
            readAloud.stop()
            Task { await listener.stop() }
        }
    }

    // MARK: - Cards

    private func options(for card: SetupCard) -> [SetupTile] {
        SetupCards.options(card: card, level: kid.readingLevel, brief: StoryBrief(interests: []), kid: kid)
    }

    private func tilePage(_ card: SetupCard) -> some View {
        let tiles = options(for: card)
        return SetupCardPage(
            prompt: card.prompt,
            tiles: tiles.map { SetupCardTileModel(id: $0.id, label: $0.label(kidName: kid.firstName), symbol: $0.symbol) },
            selectedId: answers[card]?.tileId,
            allowsOwnWords: kid.readingLevel != .listener,
            isListening: listener.isListening && step == SetupCard.allCases.firstIndex(of: card),
            heard: step == SetupCard.allCases.firstIndex(of: card) ? heardText(for: card) : "",
            onTile: { choose(.tile($0), on: card) },
            onSurprise: { surprise(card) },
            onMic: { listen(on: card, options: tiles) },
            onOwnWords: { words in BriefAnswer.answer(text: words, via: .typed).map { choose($0, on: card) } },
            onSpeakPrompt: speakPrompt
        ) {
            if card == .hero { heroDrawing }
        }
    }

    private var moodPage: some View {
        SetupCardPage(
            prompt: "How should it feel?",
            tiles: SetupCards.moods(for: kid.readingLevel).map { SetupCardTileModel(id: $0.rawValue, label: $0.label, symbol: $0.symbol) },
            selectedId: mood?.rawValue,
            allowsOwnWords: false,
            isListening: listener.isListening && step == Self.moodStep,
            heard: step == Self.moodStep ? listener.partial : "",
            onTile: { mood = StoryMood(rawValue: $0) },
            onSurprise: {
                var rng = SystemRandomNumberGenerator()
                mood = SetupCards.moods(for: kid.readingLevel).randomElement(using: &rng)
            },
            onMic: listenForMood,
            onOwnWords: { _ in },
            onSpeakPrompt: speakPrompt
        ) { EmptyView() }
    }

    /// What the card shows it heard: live words while listening, else the words it kept.
    private func heardText(for card: SetupCard) -> String {
        if listener.isListening { return listener.partial }
        if case let .text(words, _)? = answers[card] { return "“\(words)”" }
        return ""
    }

    @ViewBuilder private var heroDrawing: some View {
        VStack(spacing: 10) {
            Toggle("Draw the hero instead", isOn: $wantsHeroDrawing.animation())
                .frame(maxWidth: 420)
            if wantsHeroDrawing {
                HeroDrawingStep(canvasView: $canvasView, color: $crayonColor, description: $heroDescription)
                    .frame(maxWidth: 520)
            }
        }
    }

    // MARK: - Purpose ("what's it for", optional)

    private var purposeChips: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(StoryPurpose.allCases, id: \.self) { option in
                        Button { purpose = purpose == option ? nil : option } label: {
                            Text(option.label).modifier(SetupChipStyle(filled: purpose == option))
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            if purpose == .realMoment {
                TextField("A first day at school, a new baby…", text: $realMoment, axis: .vertical)
                    .purposeField()
            } else if purpose == .teach {
                TextField("Sharing, being brave, why leaves fall…", text: $teach, axis: .vertical)
                    .purposeField()
            }
        }
        .padding(.top, 12)
    }

    // MARK: - Start

    private var startButtons: some View {
        HStack(spacing: 12) {
            Button("Just start") { start() }
                .font(.headline)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(Theme.paperShade, in: .capsule)
                .foregroundStyle(Theme.ink)
            if step == Self.moodStep || mood != nil {
                Button { start() } label: {
                    Label("Go", systemImage: "book.fill").font(.headline)
                        .padding(.horizontal, 22).padding(.vertical, 12)
                        .background(Theme.accent, in: .capsule)
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(.vertical, 16)
    }

    private var brief: StoryBrief {
        StoryBrief(
            interests: [],
            realMoment: purpose == .realMoment ? realMoment.trimmedOrNil : nil,
            teach: purpose == .teach ? teach.trimmedOrNil : nil,
            hero: answers[.hero], place: answers[.place], problem: answers[.problem], mood: mood, purpose: purpose
        )
    }

    private var drawing: HeroDrawing? {
        guard wantsHeroDrawing, let description = heroDescription.trimmedOrNil else { return nil }
        return HeroDrawingExporter.export(canvasView, description: description)
    }

    private func start() {
        readAloud.stop()
        Task { await listener.stop() }
        onStart(brief, drawing)
    }

    // MARK: - Answering

    private func choose(_ answer: BriefAnswer, on card: SetupCard) {
        answers[card] = answer
        note = nil
        advance(from: card)
    }

    private func surprise(_ card: SetupCard) {
        var rng = SystemRandomNumberGenerator()
        guard let tile = SetupCards.surprise(card: card, level: kid.readingLevel, rng: &rng) else { return }
        choose(.tile(tile.id), on: card)
    }

    /// After an answer, the next card slides in (a beat later, so the choice is seen).
    private func advance(from card: SetupCard) {
        guard let index = SetupCard.allCases.firstIndex(of: card) else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            if step == index { withAnimation { step = index + 1 } }
        }
    }

    private func listen(on card: SetupCard, options: [SetupTile]) {
        Task {
            if listener.isListening {
                await listener.stop()
                return
            }
            readAloud.stop()
            await listener.listen(onWords: { words in
                if let tile = SetupCards.match(spoken: words, options: options, kidName: kid.firstName) {
                    choose(.tile(tile.id), on: card)
                } else if let answer = BriefAnswer.answer(text: words, via: .speech) {
                    choose(answer, on: card)
                }
            }, onFailure: { note = $0 })
        }
    }

    private func listenForMood() {
        Task {
            if listener.isListening {
                await listener.stop()
                return
            }
            readAloud.stop()
            await listener.listen(onWords: { words in
                let heard = words.lowercased()
                if let match = SetupCards.moods(for: kid.readingLevel).first(where: { heard.contains($0.rawValue) || (heard.contains("cozy") && $0 == .cosy) }) {
                    mood = match
                } else {
                    note = "Try saying one of the faces' names."
                }
            }, onFailure: { note = $0 })
        }
    }

    // MARK: - Reading the card aloud

    private func speakPrompt() {
        readAloud.read(spokenPrompt)
    }

    /// The card's question and its options as an either/or ("Who's the hero? Maya, or a dragon?").
    private var spokenPrompt: String {
        if step >= Self.moodStep {
            let faces = SetupCards.moods(for: kid.readingLevel).map(\.label)
            return "How should it feel? \(faces.formatted(.list(type: .or)))?"
        }
        let card = SetupCard.allCases[step]
        let labels = options(for: card).map { $0.label(kidName: kid.firstName) }
        return "\(card.prompt) \(labels.formatted(.list(type: .or)))?"
    }
}

private extension View {
    func purposeField() -> some View {
        padding(.horizontal, 14).padding(.vertical, 10)
            .background(.white.opacity(0.85), in: .rect(cornerRadius: 14))
            .padding(.horizontal, 24)
    }
}

extension StoryMood {
    var label: String {
        switch self {
        case .silly: "Silly"
        case .cosy: "Cosy"
        case .brave: "Brave"
        }
    }

    var symbol: String {
        switch self {
        case .silly: "face.smiling.inverse"
        case .cosy: "heart.fill"
        case .brave: "bolt.heart.fill"
        }
    }
}

extension StoryPurpose {
    var label: String {
        switch self {
        case .fun: "Just for fun"
        case .bedtime: "Bedtime"
        case .realMoment: "A real moment…"
        case .teach: "Teach something…"
        }
    }
}
