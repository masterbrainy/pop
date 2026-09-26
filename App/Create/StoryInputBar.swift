import SwiftUI

/// Who is talking: the parent narrates and directs by default; the kid can take a turn (PRD S2).
enum Speaker: String, Sendable, CaseIterable {
    case parent
    case kid
}

/// The creation controls under the text page: the mic, a text field, whose turn it is, and
/// "You continue" (the story engine writes the next bit on its own, PRD S5).
struct StoryInputBar: View {
    @Binding var speaker: Speaker
    let isListening: Bool
    let partial: String
    let isWorking: Bool
    let onToggleMic: () -> Void
    let onSubmit: (String) -> Void
    let onContinue: () -> Void

    @State private var typed = ""
    @FocusState private var typing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isListening || !partial.isEmpty {
                Text(partial.isEmpty ? "Listening…" : partial)
                    .font(.callout)
                    .foregroundStyle(Theme.softInk)
                    .lineLimit(2)
                    .transition(.opacity)
            }
            HStack(spacing: 10) {
                Button(action: onToggleMic) {
                    Image(systemName: isListening ? "stop.fill" : "mic.fill")
                        .font(.title3.weight(.semibold))
                        .frame(width: 48, height: 48)
                        .background(isListening ? Theme.accent : Theme.ink, in: .circle)
                        .foregroundStyle(.white)
                        .symbolEffect(.pulse, isActive: isListening)
                }
                .accessibilityLabel(isListening ? "Stop listening" : "Tell the story out loud")

                TextField(speaker == .parent ? "Tell or direct the story…" : "What happens next?", text: $typed, axis: .vertical)
                    .lineLimit(1...3)
                    .focused($typing)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.8), in: .rect(cornerRadius: 18))

                if !typed.isEmpty {
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 34))
                    }
                    .foregroundStyle(Theme.accent)
                    .accessibilityLabel("Add to the story")
                }
            }
            HStack {
                Picker("Who's talking", selection: $speaker) {
                    Text("Parent").tag(Speaker.parent)
                    Text("Kid").tag(Speaker.kid)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 180)
                Spacer()
                if isWorking { ProgressView().controlSize(.small) }
                Button("You continue", systemImage: "sparkles", action: onContinue)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(isWorking)
            }
            .font(.subheadline)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 22))
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
