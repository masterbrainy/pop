import PencilKit
import SwiftUI

/// The optional "Draw the hero" step in the new-book brief (ROADMAP Phase 8.2): a
/// finger-friendly canvas with a few big crayon colours, undo and clear, plus a short
/// caption for what the drawing is. `BriefSheet` exports the canvas to a PNG when the
/// parent taps Start.
struct HeroDrawingStep: View {
    @Binding var canvasView: PKCanvasView
    @Binding var color: Color
    @Binding var description: String

    private static let crayons: [Color] = [.black, .red, .orange, .yellow, .green, .blue, .purple, .brown]
    private static let swatchSize: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DrawingCanvas(canvasView: $canvasView, color: UIColor(color))
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.accent.opacity(0.35), lineWidth: 2))

            HStack(spacing: 10) {
                ForEach(Self.crayons, id: \.self) { crayon in
                    crayonSwatch(crayon)
                }
                Spacer()
                Button(action: undo) {
                    Image(systemName: "arrow.uturn.backward.circle.fill").font(.system(size: 30))
                }
                .accessibilityLabel("Undo the last stroke")
                Button(action: clear) {
                    Image(systemName: "trash.circle.fill").font(.system(size: 30))
                }
                .accessibilityLabel("Clear the drawing")
            }
            .foregroundStyle(Theme.softInk)

            TextField("What is it? A purple cat with wings…", text: $description, axis: .vertical)
        }
    }

    private func crayonSwatch(_ crayon: Color) -> some View {
        Button { color = crayon } label: {
            Circle()
                .fill(crayon)
                .frame(width: Self.swatchSize, height: Self.swatchSize)
                .overlay(Circle().strokeBorder(Theme.ink, lineWidth: color == crayon ? 3 : 0))
        }
        .accessibilityLabel("Crayon")
        .accessibilityAddTraits(color == crayon ? .isSelected : [])
    }

    private func undo() { canvasView.undoManager?.undo() }
    private func clear() { canvasView.drawing = PKDrawing() }
}
