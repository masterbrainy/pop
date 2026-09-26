import PencilKit
import PopKit
import UIKit

/// Exports a `PKCanvasView` drawing as a `HeroDrawing` (ROADMAP Phase 8.2): flattened onto
/// white (PencilKit draws on a transparent layer), longest side capped at 1024 px, and
/// downscaled further if a busy drawing's PNG still comes out over 1.5 MB.
@MainActor
enum HeroDrawingExporter {
    static let maxDimension: CGFloat = 1024
    static let maxBytes = 1_500_000
    private static let maxDownscalePasses = 4

    /// `nil` if the canvas has nothing drawn on it.
    static func export(_ canvasView: PKCanvasView, description: String) -> HeroDrawing? {
        let drawing = canvasView.drawing
        guard !drawing.strokes.isEmpty else { return nil }
        let bounds = canvasView.bounds.isEmpty ? drawing.bounds : canvasView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let longSide = max(bounds.width, bounds.height)
        let scale = longSide > maxDimension ? maxDimension / longSide : 1
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)

        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            drawing.image(from: bounds, scale: scale).draw(in: CGRect(origin: .zero, size: size))
        }

        guard let data = image.pngData() else { return nil }
        let fitted = data.count <= maxBytes ? data : (downscaled(image, targetBytes: maxBytes) ?? data)
        return HeroDrawing(imageData: fitted, description: description)
    }

    /// Shrinks `image` a few times until its PNG fits `targetBytes`, or gives up and
    /// returns the smallest size tried (PNG has no quality knob to turn instead).
    private static func downscaled(_ image: UIImage, targetBytes: Int) -> Data? {
        var current = image
        var lastData: Data?
        for _ in 0..<maxDownscalePasses {
            let size = CGSize(width: current.size.width * 0.75, height: current.size.height * 0.75)
            guard size.width > 64, size.height > 64 else { break }
            current = UIGraphicsImageRenderer(size: size).image { _ in current.draw(in: CGRect(origin: .zero, size: size)) }
            let data = current.pngData()
            lastData = data
            if let data, data.count <= targetBytes { return data }
        }
        return lastData
    }
}
