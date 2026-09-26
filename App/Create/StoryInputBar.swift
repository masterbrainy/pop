import PopKit
import SwiftUI

/// The creation controls along the bottom of the book, in one compact row: the mic and a text
/// field for directions. Everything here is the parent's (PRD S2). On a Duo the posture runs the
/// mic (angled listens, open flat reads), so the mic shows as a status instead of a button. The story path writes
/// itself (P-04); words here steer the page behind. Partial speech shows above the row.
struct StoryInputBar: View {
    let isListening: Bool
    /// The hinge decides when to listen (angled), so there's no mic button to tap.
    var listensByPosture = false
    let partial: String
    let isWorking: Bool
    let onToggleMic: () -> Void
    let onSubmit: (String) -> Void

    @State private var typed = ""
    @FocusState private var typing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isListening || !partial.isEmpty {
                Text(partial.isEmpty ? "Listening…" : partial)
                    .font(.footnote)
                    .foregroundStyle(Theme.softInk)
                    .lineLimit(2)
                    .padding(.horizontal, 6)
                    .transition(.opacity)
            }
            HStack(spacing: 8) {
                if listensByPosture {
                    Image(systemName: isListening ? "mic.fill" : "book.fill")
                        .font(.headline)
                        .frame(width: 40, height: 40)
                        .background(isListening ? Theme.accent : Theme.softInk, in: .circle)
                        .foregroundStyle(.white)
                        .symbolEffect(.pulse, isActive: isListening)
                        .contentTransition(.symbolEffect(.replace))
                        .accessibilityElement()
                        .accessibilityLabel(isListening ? "Listening. Open the phone flat to just read"
                                                        : "Reading. Angle the phone to talk")
                } else {
                    Button(action: onToggleMic) {
                        Image(systemName: isListening ? "stop.fill" : "mic.fill")
                            .font(.headline)
                            .frame(width: 40, height: 40)
                            .background(isListening ? Theme.accent : Theme.ink, in: .circle)
                            .foregroundStyle(.white)
                            .symbolEffect(.pulse, isActive: isListening)
                    }
                    .accessibilityLabel(isListening ? "Stop listening" : "Tell the story out loud")
                }

                TextField(placeholder, text: $typed)
                    .focused($typing)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .font(.callout)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.white.opacity(0.85), in: .capsule)

                // Another direction can always be sent; the spinner shows only while nothing is typed.
                if isWorking, typed.isEmpty {
                    ProgressView().controlSize(.small).frame(width: 36, height: 36)
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up")
                            .font(.subheadline.weight(.bold))
                            .frame(width: 36, height: 36)
                            .background(Theme.accent.opacity(typed.isEmpty ? 0.4 : 1), in: .circle)
                            .foregroundStyle(.white)
                    }
                    .disabled(typed.isEmpty)
                    .accessibilityLabel("Steer the story")
                }
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 26))
        .animation(.easeInOut(duration: 0.2), value: isListening)
    }

    private var placeholder: String {
        guard listensByPosture else { return "Steer what happens next…" }
        return isListening ? "Listening… or type here" : "Angle the phone to talk, or type here…"
    }

    private func send() {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        typed = ""
        typing = false
        onSubmit(text)
    }
}
