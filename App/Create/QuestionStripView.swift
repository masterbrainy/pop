import PopKit
import SwiftUI
import UIKit

/// One question per page (IMP-25): a line for the parent to read aloud, picture tiles the kid
/// can tap, "something else" (their own idea, said or typed) and Skip. It stands in for the
/// input bar while it shows. The kid's page never flashes or asks for a tap; the parent asks.
struct QuestionStripView: View {
    let question: ActiveQuestion
    let level: ReadingLevel
    let onChoose: (StoryChoice) -> Void
    let onSomethingElse: () -> Void
    let onSkip: () -> Void

    /// Readers get "something else" first and filled: choice scaffolds can cap strong storytellers.
    private var favoursOwnIdea: Bool { level == .reader }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(question.ask)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "bubble.left.and.text.bubble.right.fill").foregroundStyle(Theme.accent)
            }
            .accessibilityLabel("Ask: \(question.ask)")

            if !question.choices.isEmpty {
                HStack(spacing: 8) {
                    ForEach(question.choices, id: \.self) { choice in
                        ChoiceTile(choice: choice) { onChoose(choice) }
                    }
                }
            }

            HStack(spacing: 8) {
                Button(action: onSomethingElse) {
                    Label("Something else", systemImage: "mic.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(favoursOwnIdea ? Theme.accent : Theme.paperShade, in: .capsule)
                        .foregroundStyle(favoursOwnIdea ? .white : Theme.ink)
                }
                .accessibilityHint("Say or type your own idea")
                Spacer()
                Button(question.choices.isEmpty ? "Done" : "Skip", action: onSkip)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.softInk)
            }

            // Only below the Reader level, where the child won't read it.
            if level != .reader {
                Text("Tip: praise the answer, then ask why.")
                    .font(.caption)
                    .foregroundStyle(Theme.softInk)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 22))
    }
}

/// A tap-to-steer tile: a big symbol over a short caption.
private struct ChoiceTile: View {
    let choice: StoryChoice
    let action: () -> Void

    /// Symbols come from the server's allow-list; one this system lacks shows a star.
    private var symbol: String { UIImage(systemName: choice.symbol) == nil ? "star.fill" : choice.symbol }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 28, weight: .semibold))
                Text(choice.label).font(.footnote.weight(.semibold)).lineLimit(2).multilineTextAlignment(.center)
            }
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 78)
            .padding(.horizontal, 6)
            .background(.white.opacity(0.85), in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.label)
    }
}
