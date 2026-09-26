import PencilKit
import PopKit
import SwiftUI

/// The per-book story brief (ROADMAP Phase 2): what the kid loves, an optional real moment
/// to help with, an optional "Anything you'd like this story to teach?" that simply goes
/// into the prompt, and an optional finger drawing of the story's hero (ROADMAP Phase 8.2).
/// Everything is optional except starting, and the child's first name when none is saved yet.
struct BriefSheet: View {
    let kid: KidProfile
    /// The brief, the optional hero drawing, and the child's first name.
    let onStart: (StoryBrief, HeroDrawing?, String) -> Void
    var onCancel: () -> Void = {}

    @State private var firstName: String
    @State private var interests: String
    @State private var realMoment = ""
    @State private var teach = ""
    @State private var wantsHeroDrawing = false
    @State private var canvasView = PKCanvasView()
    @State private var crayonColor: Color = .red
    @State private var heroDescription = ""

    init(kid: KidProfile, onStart: @escaping (StoryBrief, HeroDrawing?, String) -> Void, onCancel: @escaping () -> Void = {}) {
        self.kid = kid
        self.onStart = onStart
        self.onCancel = onCancel
        _firstName = State(initialValue: kid.firstName)
        _interests = State(initialValue: kid.interests.joined(separator: ", "))
    }

    var body: some View {
        NavigationStack {
            Form {
                if kid.firstName.isEmpty {
                    Section {
                        TextField("First name only", text: $firstName)
                            .textContentType(.givenName)
                    } header: {
                        Text("Who is this story for?")
                    } footer: {
                        Text("You can change this later in parent settings.")
                    }
                }
                Section {
                    TextField("Dinosaurs, the moon, our dog Biscuit…", text: $interests, axis: .vertical)
                } header: {
                    Text("What does \(childName ?? "your child") love?")
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
                Section {
                    Toggle("Draw the hero", isOn: $wantsHeroDrawing.animation())
                    if wantsHeroDrawing {
                        HeroDrawingStep(canvasView: $canvasView, color: $crayonColor, description: $heroDescription)
                    }
                } header: {
                    Text("A drawing (optional)")
                } footer: {
                    Text("Draw with a finger, then say what it is. Pop! turns it into the story's hero.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
            .navigationTitle("A new story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        if let childName { onStart(brief, heroDrawing, childName) }
                    }
                    .fontWeight(.semibold)
                    .disabled(childName == nil)
                }
            }
        }
    }

    /// The first word of the name field, or nil while it's empty.
    private var childName: String? {
        firstName.split(separator: " ").first.map(String.init)
    }

    private var brief: StoryBrief {
        StoryBrief(
            interests: interests.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
            realMoment: realMoment.trimmedOrNil,
            teach: teach.trimmedOrNil
        )
    }

    private var heroDrawing: HeroDrawing? {
        guard wantsHeroDrawing, let description = heroDescription.trimmedOrNil else { return nil }
        return HeroDrawingExporter.export(canvasView, description: description)
    }
}

extension String {
    var trimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
