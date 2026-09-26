import SwiftUI

/// Shown after Begin until the first page is alive: which step the first page is on (writing
/// its words, painting its picture, bringing it to life), with the parent's idea above.
struct OpeningLoadingView: View {
    let stage: StoryMaker.OpeningStage
    let idea: String?

    private struct Step: Identifiable {
        let stage: StoryMaker.OpeningStage
        let title: String
        let symbol: String
        var id: String { title }
    }

    private static let steps = [
        Step(stage: .writing, title: "Writing the first page", symbol: "pencil.and.scribble"),
        Step(stage: .painting, title: "Painting the picture", symbol: "paintbrush.pointed"),
        Step(stage: .animating, title: "Bringing it to life", symbol: "sparkles"),
    ]

    private var currentStep: Int {
        Self.steps.firstIndex { $0.stage == stage } ?? 0
    }

    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: Self.steps[currentStep].symbol)
                .font(.system(size: 56))
                .foregroundStyle(Theme.accent)
                .symbolEffect(.breathe)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)

            if let idea {
                Text("“\(idea)”")
                    .font(Theme.storyFont(size: 22))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: 480)
            }

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(Self.steps.enumerated()), id: \.element.id) { index, step in
                    HStack(spacing: 12) {
                        Group {
                            if index < currentStep {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                            } else if index == currentStep {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "circle").foregroundStyle(Theme.softInk.opacity(0.5))
                            }
                        }
                        .frame(width: 22)
                        Text(step.title)
                            .font(.body.weight(index == currentStep ? .semibold : .regular))
                            .foregroundStyle(index > currentStep ? Theme.softInk : Theme.ink)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(index < currentStep ? "Done" : index == currentStep ? "In progress" : "Waiting")
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper)
        .animation(.smooth, value: stage)
    }
}
