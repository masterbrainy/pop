import PopKit
import SwiftUI

/// The creation controls along the bottom of the book, in one compact row: the mic, a text
/// field for directions, and whose turn it is (parent or kid, PRD S2). The story path writes
/// itself (P-04); words here steer the page behind. Partial speech shows above the row.
struct StoryInputBar: View {
    @Binding var speaker: Speaker
    let isListening: Bool
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
                Button(action: onToggleMic) {
                    Image(systemName: isListening ? "stop.fill" : "mic.fill")
                        .font(.headline)
                        .frame(width: 40, height: 40)
                        .background(isListening ? Theme.accent : Theme.ink, in: .circle)
                        .foregroundStyle(.white)
                        .symbolEffect(.pulse, isActive: isListening)
                }
                .accessibilityLabel(isListening ? "Stop listening" : "Tell the story out loud")

                TextField(speaker == .parent ? "Steer what happens next…" : "What happens next?", text: $typed)
                    .focused($typing)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .font(.callout)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.white.opacity(0.85), in: .capsule)

                Button {
                    speaker = speaker == .parent ? .kid : .parent
                } label: {
                    Image(systemName: speaker == .parent ? "person.fill" : "figure.child")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .background(Theme.paperShade, in: .circle)
                }
                .foregroundStyle(Theme.ink)
                .accessibilityLabel(speaker == .parent ? "Parent is talking. Switch to kid" : "Kid is talking. Switch to parent")

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

    private func send() {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        typed = ""
        typing = false
        onSubmit(text)
    }
}
