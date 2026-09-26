import SwiftUI

/// A simple parental gate (ROADMAP Phase 6): a sum a young kid can't do yet, shown before
/// parent settings and sharing.
struct ParentGate: View {
    let onPass: () -> Void
    var onCancel: () -> Void = {}

    @State private var question = ParentGate.makeQuestion()
    @State private var answer = ""
    @State private var wrong = false

    var body: some View {
        VStack(spacing: 20) {
            Text("For grown-ups").font(Theme.titleFont(size: 24))
            Text("What is \(question.a) × \(question.b)?").font(Theme.storyFont(size: 22))
            TextField("Answer", text: $answer)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.title2)
                .frame(width: 140)
                .padding(10)
                .background(.white, in: .rect(cornerRadius: 12))
                .onSubmit(check)
            if wrong { Text("Not quite. Try this one.").foregroundStyle(Theme.accent) }
            HStack(spacing: 16) {
                Button("Cancel", action: onCancel).buttonStyle(.bordered)
                Button("Continue", action: check).buttonStyle(.borderedProminent).tint(Theme.accent)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper)
    }

    private func check() {
        if Int(answer) == question.a * question.b {
            onPass()
        } else {
            wrong = true
            answer = ""
            question = Self.makeQuestion()
        }
    }

    private static func makeQuestion() -> (a: Int, b: Int) {
        (Int.random(in: 6...9), Int.random(in: 6...9))
    }
}
