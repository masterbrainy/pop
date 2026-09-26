import PopKit
import SwiftUI

/// The per-book story brief: the guided setup's four picture cards (IMP-24, `SetupCardsView`),
/// with an optional real moment, an optional "teach something" that simply goes into the
/// prompt, and an optional finger drawing of the hero (ROADMAP Phase 8.2). Everything is
/// optional except starting.
struct BriefSheet: View {
    let kid: KidProfile
    let onStart: (StoryBrief, HeroDrawing?) -> Void
    var onCancel: () -> Void = {}

    var body: some View {
        NavigationStack {
            SetupCardsView(kid: kid, onStart: onStart)
                .navigationTitle("A new story")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                }
        }
    }
}

extension String {
    var trimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
