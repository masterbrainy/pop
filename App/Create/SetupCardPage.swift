import PopKit
import SwiftUI

/// One guided-setup card (IMP-24): its question, 2 or 3 big picture tiles, "Surprise me", a mic,
/// and for older kids "something else" in their own words.
struct SetupCardPage<Extra: View>: View {
    let prompt: String
    let tiles: [SetupCardTileModel]
    let selectedId: String?
    let allowsOwnWords: Bool
    let isListening: Bool
    let heard: String
    let onTile: (String) -> Void
    let onSurprise: () -> Void
    let onMic: () -> Void
    let onOwnWords: (String) -> Void
    let onSpeakPrompt: () -> Void
    @ViewBuilder var extra: () -> Extra

    @State private var ownWords = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack(spacing: 10) {
                    Text(prompt).font(Theme.titleFont(size: 28)).foregroundStyle(Theme.ink)
                    Button(action: onSpeakPrompt) {
                        Image(systemName: "speaker.wave.2.fill").font(.headline).padding(10).background(Theme.paperShade, in: .circle)
                    }
                    .foregroundStyle(Theme.ink)
                    .accessibilityLabel("Read the question aloud")
                }
                .padding(.top, 8)

                HStack(spacing: 14) {
                    ForEach(tiles) { tile in
                        SetupTileButton(tile: tile, isSelected: tile.id == selectedId) { onTile(tile.id) }
                    }
                }

                HStack(spacing: 12) {
                    Button(action: onSurprise) {
                        Label("Surprise me", systemImage: "dice.fill").modifier(SetupChipStyle(filled: false))
                    }
                    Button(action: onMic) {
                        Label(isListening ? "Listening…" : "Say it", systemImage: isListening ? "stop.fill" : "mic.fill")
                            .modifier(SetupChipStyle(filled: isListening))
                    }
                    .accessibilityLabel(isListening ? "Stop listening" : "Answer out loud")
                }
                if isListening || !heard.isEmpty {
                    Text(heard.isEmpty ? "Listening…" : heard).font(.footnote).foregroundStyle(Theme.softInk)
                }

                if allowsOwnWords {
                    HStack(spacing: 8) {
                        TextField("Something else…", text: $ownWords)
                            .submitLabel(.done)
                            .onSubmit(sendOwnWords)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(.white.opacity(0.85), in: .capsule)
                        Button("Use", action: sendOwnWords).disabled(ownWords.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .frame(maxWidth: 420)
                }
                extra()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
    }

    private func sendOwnWords() {
        let words = ownWords.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        ownWords = ""
        onOwnWords(words)
    }
}

/// What a card's tile shows; mood faces use the same button.
struct SetupCardTileModel: Identifiable, Equatable {
    let id: String
    let label: String
    let symbol: String
}

private struct SetupTileButton: View {
    let tile: SetupCardTileModel
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: tile.symbol).font(.system(size: 44, weight: .semibold))
                Text(tile.label).font(.headline).lineLimit(2).multilineTextAlignment(.center)
            }
            .foregroundStyle(isSelected ? .white : Theme.ink)
            .frame(width: 128, height: 128)
            .background(isSelected ? Theme.accent : .white.opacity(0.9), in: .rect(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Theme.accent.opacity(isSelected ? 0 : 0.35), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tile.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct SetupChipStyle: ViewModifier {
    let filled: Bool

    func body(content: Content) -> some View {
        content
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(filled ? Theme.accent : Theme.paperShade, in: .capsule)
            .foregroundStyle(filled ? .white : Theme.ink)
    }
}
