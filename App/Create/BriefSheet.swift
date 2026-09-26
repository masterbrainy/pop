import PopKit
import SwiftUI

/// The per-book story brief (ROADMAP Phase 2): what the kid loves, an optional real moment
/// to help with, and an optional "Anything you'd like this story to teach?" that simply goes
/// into the prompt. Everything is optional except starting.
struct BriefSheet: View {
    let kid: KidProfile
    let onStart: (StoryBrief) -> Void
    var onCancel: () -> Void = {}

    @State private var interests: String
    @State private var realMoment = ""
    @State private var teach = ""

    init(kid: KidProfile, onStart: @escaping (StoryBrief) -> Void, onCancel: @escaping () -> Void = {}) {
        self.kid = kid
        self.onStart = onStart
        self.onCancel = onCancel
        _interests = State(initialValue: kid.interests.joined(separator: ", "))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Dinosaurs, the moon, our dog Biscuit…", text: $interests, axis: .vertical)
                } header: {
                    Text("What does \(kid.firstName) love?")
                }
                Section {
                    TextField("A first day at school, a new baby…", text: $realMoment, axis: .vertical)
                } header: {
                    Text("A real moment (optional)")
                } footer: {
                    Text("The story helps with it gently and never uses real names, schools or places.")
                }
                Section {
                    TextField("Sharing, being brave, why leaves fall…", text: $teach, axis: .vertical)
                } header: {
                    Text("Anything you'd like this story to teach? (optional)")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
            .navigationTitle("A new story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") { onStart(brief) }.fontWeight(.semibold)
                }
            }
        }
    }

    private var brief: StoryBrief {
        StoryBrief(
            interests: interests.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
            realMoment: realMoment.trimmedOrNil,
            teach: teach.trimmedOrNil
        )
    }
}

extension String {
    var trimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
