import UIKit

/// Resolves a page's `stillPath` (and other media paths) to an image: `asset:<name>` for
/// bundled sample art, or an absolute file path for pictures cached on the device.
/// Files are cached in memory: each picture is stored under its own name (page id and version),
/// so a cached copy never goes stale, and the pages redraw often as the hinge moves.
enum StillImageLoader {
    nonisolated(unsafe) private static let cache = NSCache<NSString, UIImage>()

    static func image(for path: String?) -> UIImage? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("asset:") {
            return UIImage(named: String(path.dropFirst("asset:".count)))
        }
        guard path.hasPrefix("/") else { return nil }
        if let cached = cache.object(forKey: path as NSString) { return cached }
        guard let image = UIImage(contentsOfFile: path) else { return nil }
        cache.setObject(image, forKey: path as NSString)
        return image
    }

    /// The bytes to send to Orbis: the file as stored, or bundled art re-encoded as JPEG.
    static func data(for path: String?) -> Data? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("/") { return FileManager.default.contents(atPath: path) }
        return image(for: path)?.jpegData(compressionQuality: 0.9)
    }

    static func url(for path: String?) -> URL? {
        guard let path, path.hasPrefix("/") else { return nil }
        return URL(filePath: path)
    }
}
