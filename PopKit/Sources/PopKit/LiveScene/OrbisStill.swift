import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The still Orbis animates from. Stills are stored as 1344×768 PNGs (about 1.8 MB), but
/// Orbis Stable works at 832×480, so it gets a JPEG at that size instead (about a tenth of
/// the bytes), which shortens the upload inside every page's prepare.
public enum OrbisStill {
    /// Orbis Stable's native width (ROADMAP §3).
    public static let maxSide = 832
    public static let jpegQuality = 0.85

    /// `data` scaled so its long side is at most `maxSide` (never up), as a JPEG; nil if
    /// `data` isn't an image ImageIO can read.
    public static func jpeg(from data: Data, maxSide: Int = maxSide, quality: Double = jpegQuality) -> Data? {
        guard !data.isEmpty, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
