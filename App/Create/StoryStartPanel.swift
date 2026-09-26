import PopKit
import SwiftUI

/// The empty first page of a new book: nothing is written until the parent gives an idea for
/// how the story begins (typed or said in the bar below) and taps Begin.
struct StoryStartPanel: View {
    let ideas: [StoryTurnInput]
    let onRemove: (Int) -> Void
    let onBegin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How does the story begin?")
                .font(Theme.titleFont(size: 28))
                .foregroundStyle(Theme.ink)
            Text(ideas.isEmpty
                 ? "Type or say an idea below, like “a shy dragon who wants a friend”."
                 : "Add more if you like, then tap Begin.")
                .font(.callout)
                .foregroundStyle(Theme.softInk)

            if !ideas.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(ideas.enumerated()), id: \.offset) { index, idea in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: idea.kind == .speech ? "waveform" : "text.bubble")
                                .foregroundStyle(Theme.accent)
                                .accessibilityHidden(true)
                            Text(idea.text)
                                .font(Theme.storyFont(size: 18))
                                .foregroundStyle(Theme.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button("Remove", systemImage: "xmark") { onRemove(index) }
                                .labelStyle(.iconOnly)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.softInk)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Theme.paperShade, in: .rect(cornerRadius: 14))
                    }
                }
            }

            Button(action: onBegin) {
                Label("Begin", systemImage: "book")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(ideas.isEmpty ? AnyShapeStyle(Theme.softInk.opacity(0.25)) : AnyShapeStyle(Theme.accent),
                                in: .capsule)
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(ideas.isEmpty)
            .accessibilityHint(ideas.isEmpty ? "Give an idea for how the story begins first" : "Writes the first page")
        }
        .frame(maxWidth: 420)
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper)
        .animation(.smooth, value: ideas)
    }
}
