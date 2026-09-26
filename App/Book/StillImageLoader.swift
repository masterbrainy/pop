import PopKit
import UIKit

/// Resolves a page's `stillPath` (and other media paths) to an image: `asset:<name>` for
/// bundled sample art, or an absolute file path for pictures cached on the device.
enum StillImageLoader {
    static func image(for path: String?) -> UIImage? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("asset:") {
            return UIImage(named: String(path.dropFirst("asset:".count)))
        }
        if path.hasPrefix("/") {
            return UIImage(contentsOfFile: path)
        }
        return nil
    }

    /// A page still or background plate cropped to Orbis's 16:9 frame, so the still and the
    /// live video show the same picture and the handover doesn't zoom (R-50). Not for cutouts.
    static func frameImage(for path: String?) -> UIImage? {
        guard let image = image(for: path) else { return nil }
        guard let cgImage = image.cgImage else { return image }
        let cropped = OrbisStill.croppedToFrame(cgImage)
        return cropped === cgImage ? image : UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
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
