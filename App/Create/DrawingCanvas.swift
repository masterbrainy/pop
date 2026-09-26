import PencilKit
import SwiftUI

/// A finger-friendly `PKCanvasView` for the kid's hero drawing (ROADMAP Phase 8.2): any
/// finger or Pencil stroke works (no palette, ruler or zoom), on a plain white background
/// so the exported PNG needs no separate flattening step for colour.
struct DrawingCanvas: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    var color: UIColor
    var lineWidth: CGFloat = 18

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.drawingPolicy = .anyInput
        canvasView.backgroundColor = .white
        canvasView.isOpaque = true
        canvasView.tool = PKInkingTool(.crayon, color: color, width: lineWidth)
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        uiView.tool = PKInkingTool(.crayon, color: color, width: lineWidth)
    }
}
