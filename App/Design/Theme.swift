import SwiftUI

/// Pop!'s look: warm paper, soft ink, one accent. Picture-book calm, not app chrome.
enum Theme {
    static let paper = Color(red: 0.99, green: 0.97, blue: 0.92)
    static let paperShade = Color(red: 0.93, green: 0.89, blue: 0.81)
    static let ink = Color(red: 0.22, green: 0.17, blue: 0.13)
    static let softInk = Color(red: 0.45, green: 0.39, blue: 0.33)
    static let accent = Color(red: 0.96, green: 0.47, blue: 0.29)
    static let coverTop = Color(red: 0.98, green: 0.62, blue: 0.40)
    static let coverBottom = Color(red: 0.86, green: 0.36, blue: 0.33)

    static func storyFont(size: Double) -> Font {
        .system(size: size, weight: .medium, design: .serif)
    }

    static func titleFont(size: Double) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
}
