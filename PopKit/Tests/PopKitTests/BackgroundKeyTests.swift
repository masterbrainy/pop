import CoreGraphics
import Testing
@testable import PopKit

@Suite struct BackgroundKeyTests {
    /// A `size`×`size` RGBA image filled with `background`, with a `square`-sized block of
    /// `subject` in the middle.
    private func image(size: Int, background: (UInt8, UInt8, UInt8), subject: (UInt8, UInt8, UInt8), square: Int) -> CGImage {
        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        let lower = (size - square) / 2
        for y in 0..<size {
            for x in 0..<size {
                let inside = (lower..<(lower + square)).contains(x) && (lower..<(lower + square)).contains(y)
                let color = inside ? subject : background
                let offset = (y * size + x) * 4
                pixels[offset] = color.0
                pixels[offset + 1] = color.1
                pixels[offset + 2] = color.2
            }
        }
        let context = CGContext(data: &pixels, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }

    private func alpha(of image: CGImage, x: Int, y: Int) -> UInt8 {
        let pixels = BackgroundKey.rgba(image)!
        return pixels[(y * image.width + x) * 4 + 3]
    }

    @Test func removesTheBackgroundConnectedToTheEdges() throws {
        let source = image(size: 40, background: (128, 200, 100), subject: (230, 80, 60), square: 10)
        let keyed = try #require(BackgroundKey.removeBackground(from: source))
        #expect(alpha(of: keyed, x: 0, y: 0) == 0)
        #expect(alpha(of: keyed, x: 5, y: 20) == 0)
        #expect(alpha(of: keyed, x: 20, y: 20) == 255)
    }

    @Test func keepsASubjectTheSameColourAsTheBackgroundWhenItIsEnclosed() throws {
        // A red ring encloses a background-coloured centre: the centre isn't reachable from
        // the edges, so it stays (a green dragon on a green field keeps its green belly).
        var source = image(size: 40, background: (128, 200, 100), subject: (230, 80, 60), square: 20)
        source = try #require(BackgroundKey.paint(source, rect: (15, 15, 10, 10), color: (128, 200, 100)))
        let keyed = try #require(BackgroundKey.removeBackground(from: source))
        #expect(alpha(of: keyed, x: 20, y: 20) == 255)
        #expect(alpha(of: keyed, x: 1, y: 1) == 0)
    }

    @Test func toleratesWatercolourNoiseInTheBackground() throws {
        var source = image(size: 40, background: (128, 200, 100), subject: (230, 80, 60), square: 10)
        source = try #require(BackgroundKey.paint(source, rect: (2, 2, 6, 6), color: (140, 210, 112)))
        let keyed = try #require(BackgroundKey.removeBackground(from: source))
        #expect(alpha(of: keyed, x: 4, y: 4) == 0)
    }
}
