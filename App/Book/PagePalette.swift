import CoreImage
import SwiftUI
import UIKit

/// Colours for the text page taken from its illustration, so the words sit in the same
/// world as the picture: a faint wash of the picture's average colour over the paper, and
/// ink tinted toward it. Cached per still, since the page redraws often.
@MainActor
struct PagePalette {
    let wash: Color
    let ink: Color

    static let plain = PagePalette(wash: Theme.paper, ink: Theme.ink)

    /// How much of the picture's colour tints the paper and the ink.
    private static let washStrength = 0.16
    private static let inkStrength = 0.35
    /// Darkest the tinted ink may be relative to the picture's colour, so text stays readable.
    private static let inkBrightness = 0.22

    private static let cache = NSCache<NSString, Box>()
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    static func of(_ image: UIImage?, key: String?) -> PagePalette {
        guard let image, let key else { return .plain }
        if let cached = cache.object(forKey: key as NSString) { return cached.palette }
        let palette = averageColor(of: image).map(palette(around:)) ?? .plain
        cache.setObject(Box(palette), forKey: key as NSString)
        return palette
    }

    private static func palette(around color: UIColor) -> PagePalette {
        let paper = UIColor(Theme.paper), ink = UIColor(Theme.ink)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let deepTone = UIColor(hue: hue, saturation: min(saturation * 1.2, 0.8), brightness: inkBrightness, alpha: 1)
        return PagePalette(wash: Color(mix(paper, color, washStrength)), ink: Color(mix(ink, deepTone, inkStrength)))
    }

    private static func mix(_ base: UIColor, _ other: UIColor, _ amount: Double) -> UIColor {
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        base.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = CGFloat(amount)
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, alpha: 1)
    }

    private static func averageColor(of image: UIImage) -> UIColor? {
        guard let input = CIImage(image: image),
              let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: input, kCIInputExtentKey: CIVector(cgRect: input.extent)]),
              let output = filter.outputImage
        else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return UIColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1)
    }

    private final class Box {
        let palette: PagePalette
        init(_ palette: PagePalette) { self.palette = palette }
    }
}

/// The text page's backdrop: the page's own illustration, mirrored and washed out like a
/// faint watercolor echo along the bottom, fading to clear paper where the words sit.
struct TextPageBackdrop: View {
    let image: UIImage?
    let palette: PagePalette

    /// How strongly the echo of the picture shows at the very bottom of the page.
    private static let echoOpacity = 0.42

    var body: some View {
        ZStack {
            palette.wash
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(x: -1, y: 1)
                    .saturation(0.75)
                    .blur(radius: 1.2)
                    .opacity(Self.echoOpacity)
                    .blendMode(.multiply)
                    .mask(
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .clear, location: 0.38),
                            .init(color: .black.opacity(0.55), location: 0.68),
                            .init(color: .black, location: 1.0),
                        ], startPoint: .top, endPoint: .bottom)
                    )
                    .accessibilityHidden(true)
            }
        }
        .clipped()
    }
}
