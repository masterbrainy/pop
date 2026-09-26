import CoreImage
import SwiftUI
import UIKit

/// Pastel colours for the text page, taken from its illustration so the words sit in the same
/// world as the picture: the paper is a soft gradient from the picture's top colour to its
/// bottom colour, with a wash of its overall colour, and the ink and read-along accent lean
/// toward its hue. Cached per still, since the page redraws often.
@MainActor
struct PagePalette: Equatable {
    /// The paper at the top and bottom of the page.
    let top: Color
    let bottom: Color
    /// The picture's overall colour, as a pastel, for the soft blobs on the paper.
    let wash: Color
    let ink: Color
    /// The spoken word and the bouncing ball.
    let accent: Color

    static let plain = PagePalette(top: Theme.paper, bottom: Theme.paper, wash: Theme.paper, ink: Theme.ink, accent: Theme.accent)

    private static let cache = NSCache<NSString, Box>()
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    static func of(_ image: UIImage?, key: String?) -> PagePalette {
        guard let image, let key else { return .plain }
        if let cached = cache.object(forKey: key as NSString) { return cached.palette }
        let palette = make(from: image) ?? .plain
        cache.setObject(Box(palette), forKey: key as NSString)
        return palette
    }

    private static func make(from image: UIImage) -> PagePalette? {
        guard let input = CIImage(image: image) else { return nil }
        let extent = input.extent
        let third = extent.height / 3
        // Core Image's origin is bottom-left: the top of the picture is the highest band.
        let topBand = CGRect(x: extent.minX, y: extent.maxY - third, width: extent.width, height: third)
        let bottomBand = CGRect(x: extent.minX, y: extent.minY, width: extent.width, height: third)
        guard let overall = average(of: input, in: extent),
              let top = average(of: input, in: topBand),
              let bottom = average(of: input, in: bottomBand)
        else { return nil }
        let main = HSB(overall)
        return PagePalette(
            top: Color(pastel(HSB(top), brightness: 0.97)),
            bottom: Color(pastel(HSB(bottom), brightness: 0.93)),
            wash: Color(pastel(main, brightness: 0.9, saturationScale: 0.9)),
            ink: Color(UIColor(hue: main.hue, saturation: min(max(main.saturation, 0.25), 0.55), brightness: 0.26, alpha: 1)),
            accent: Color(UIColor(hue: main.hue, saturation: min(max(main.saturation * 1.3, 0.45), 0.7), brightness: 0.8, alpha: 1))
        )
    }

    /// Light and softly coloured: the picture's hue with its saturation turned down.
    private static func pastel(_ color: HSB, brightness: CGFloat, saturationScale: CGFloat = 0.55) -> UIColor {
        UIColor(hue: color.hue, saturation: min(max(color.saturation * saturationScale, 0.1), 0.32), brightness: brightness, alpha: 1)
    }

    private static func average(of image: CIImage, in rect: CGRect) -> UIColor? {
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: image, kCIInputExtentKey: CIVector(cgRect: rect)]),
              let output = filter.outputImage
        else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return UIColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1)
    }

    private struct HSB {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0

        init(_ color: UIColor) {
            var alpha: CGFloat = 0
            color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        }
    }

    private final class Box {
        let palette: PagePalette
        init(_ palette: PagePalette) { self.palette = palette }
    }
}
