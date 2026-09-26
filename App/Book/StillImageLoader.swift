import UIKit

/// Resolves a page's `stillPath` to an image: `asset:<name>` for bundled sample art, or an
/// absolute file path for pictures cached on the device. Storage paths arrive in Phase 2.
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
}
