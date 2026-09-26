import CoreGraphics
import Foundation
import Testing
@testable import PopKit

/// Covers `ChromaKey.apply`: a flat chroma-green field becomes transparent while
/// a red square keyed on top of it stays opaque (docs/CONTRACTS.md §3 `cutout`/`plate`).
struct ChromaKeyTests {
    /// A 4×4 image: green everywhere, except a solid red 2×2 square in the middle.
    private func greenFieldWithARedSquare() -> CGImage {
        let size = 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 1, y: 1, width: 2, height: 2))
        return context.makeImage()!
    }

    private func alpha(of image: CGImage, x: Int, y: Int) -> UInt8 {
        let data = image.dataProvider!.data! as Data
        let bytesPerRow = image.bytesPerRow
        let bytesPerPixel = image.bitsPerPixel / 8
        let offset = y * bytesPerRow + x * bytesPerPixel
        return data[data.startIndex + offset + 3]
    }

    @Test func greenBecomesTransparentAndRedStaysOpaque() throws {
        let source = greenFieldWithARedSquare()
        let keyed = try #require(ChromaKey.apply(to: source))

        #expect(keyed.width == source.width)
        #expect(keyed.height == source.height)

        // corners are still green: fully transparent.
        #expect(alpha(of: keyed, x: 0, y: 0) == 0)
        #expect(alpha(of: keyed, x: 3, y: 3) == 0)

        // the middle 2x2 is red: fully opaque.
        #expect(alpha(of: keyed, x: 1, y: 1) == 255)
        #expect(alpha(of: keyed, x: 2, y: 2) == 255)
    }

    @Test func aTighterToleranceStillKeysExactChromaGreen() throws {
        let source = greenFieldWithARedSquare()
        let keyed = try #require(ChromaKey.apply(to: source, tolerance: 0.05))

        #expect(alpha(of: keyed, x: 0, y: 0) == 0)
        #expect(alpha(of: keyed, x: 1, y: 1) == 255)
    }

    @Test func aDifferentChromaColorKeysThatColorInstead() throws {
        let source = greenFieldWithARedSquare()
        // Key on red instead: now the square disappears and the green field stays.
        let keyed = try #require(ChromaKey.apply(to: source, chroma: ChromaKey.Color(red: 1, green: 0, blue: 0)))

        #expect(alpha(of: keyed, x: 0, y: 0) == 255)
        #expect(alpha(of: keyed, x: 1, y: 1) == 0)
    }
}
