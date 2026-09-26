import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import PopKit

/// Covers `OrbisStill.jpeg`: the stored 1344×768 PNG still goes to Orbis as a small
/// JPEG at about its native 832×480, which shortens upload and prepare.
struct OrbisStillTests {
    /// An opaque image with painterly per-pixel variation (a seeded pseudo-random walk), so
    /// PNG can't compress it away the way it would a flat test pattern.
    private func png(width: Int, height: Int) -> Data {
        var seed: UInt32 = 12_345
        var value = 128
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            for channel in 0..<3 {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                value = min(255, max(0, value + Int(seed >> 28) - 7))
                pixels[index + channel] = UInt8((value + channel * 60) % 256)
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return output as Data
    }

    private func size(of data: Data) -> (width: Int, height: Int, type: String)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              let type = CGImageSourceGetType(source) as String?
        else { return nil }
        return (width, height, type)
    }

    @Test func aStoredStillBecomesAnOrbisSizedJPEG() throws {
        let still = png(width: 1344, height: 768)
        let jpeg = try #require(OrbisStill.jpeg(from: still))
        let info = try #require(size(of: jpeg))
        #expect(info.type == UTType.jpeg.identifier)
        #expect(info.width == 832)
        #expect(info.height == 475) // keeps the still's shape
        #expect(jpeg.count < still.count)
    }

    @Test func anOpenAIPageStillIsCroppedToSixteenByNine() throws {
        let jpeg = try #require(OrbisStill.jpeg(from: png(width: 1536, height: 1024)))
        let info = try #require(size(of: jpeg))
        #expect(info.width == 832)
        #expect(info.height == 468) // 3:2 centre-cropped to 16:9
    }

    @Test func aPortraitStillIsNotCropped() throws {
        let jpeg = try #require(OrbisStill.jpeg(from: png(width: 1024, height: 1536)))
        let info = try #require(size(of: jpeg))
        #expect(info.width == 555 && info.height == 832)
    }

    @Test func aSmallerStillIsNotUpscaled() throws {
        let jpeg = try #require(OrbisStill.jpeg(from: png(width: 640, height: 360)))
        let info = try #require(size(of: jpeg))
        #expect(info.width == 640 && info.height == 360)
    }

    @Test func dataThatIsNotAnImageGivesNil() {
        #expect(OrbisStill.jpeg(from: Data("not an image".utf8)) == nil)
        #expect(OrbisStill.jpeg(from: Data()) == nil)
    }
}
