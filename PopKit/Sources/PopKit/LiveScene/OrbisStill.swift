import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The still Orbis animates from. Page stills are stored as PNGs (OpenAI paints 1536×1024),
/// but Orbis Stable works at 16:9 around 832×480, so it gets a 16:9 JPEG at that size
/// instead (about a tenth of the bytes), which shortens the upload inside every page's prepare.
public enum OrbisStill {
    /// Orbis Stable's native width (ROADMAP §3).
    public static let maxSide = 832
    public static let jpegQuality = 0.85
    /// Orbis's frame shape. A landscape still further from it than `cropTolerance` is
    /// centre-cropped to it; OpenAI has no 16:9 size, so its 3:2 pages always are.
    public static let aspectRatio = 16.0 / 9.0
    public static let cropTolerance = 0.03

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
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = croppedToFrame(thumbnail)
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// Centre-crops a landscape image to `aspectRatio` when it's noticeably off; portrait
    /// and near-16:9 images come back unchanged.
    static func croppedToFrame(_ image: CGImage) -> CGImage {
        let width = Double(image.width), height = Double(image.height)
        guard width > height, abs(width / height - aspectRatio) / aspectRatio > cropTolerance else { return image }
        let rect: CGRect
        if width / height > aspectRatio {
            let cropWidth = (height * aspectRatio).rounded()
            rect = CGRect(x: ((width - cropWidth) / 2).rounded(), y: 0, width: cropWidth, height: height)
        } else {
            let cropHeight = (width / aspectRatio).rounded()
            rect = CGRect(x: 0, y: ((height - cropHeight) / 2).rounded(), width: width, height: cropHeight)
        }
        return image.cropping(to: rect) ?? image
    }
}
