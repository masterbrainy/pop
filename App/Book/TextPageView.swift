import PopKit
import SwiftUI

/// The left page: the story text at the kid's reading level (PRD P1), padded clear of the
/// fold and camera.
struct TextPageView: View {
    let text: String
    let level: ReadingLevel
    let pageNumber: Int
    var placeholder = "Tell the story, and the words appear here."

    private var fontSize: Double { level.minimumTextSize + 4 }

    var body: some View {
        GeometryReader { proxy in
            let insets = ReservedRegionInsets.insets(for: proxy)
            ZStack(alignment: .bottom) {
                Theme.paper
                Text(text.isEmpty ? placeholder : text)
                    .font(Theme.storyFont(size: fontSize))
                    .foregroundStyle(text.isEmpty ? Theme.softInk : Theme.ink)
                    .lineSpacing(fontSize * 0.25)
                    // P1: never smaller than the level's minimum size.
                    .minimumScaleFactor(level.minimumTextSize / fontSize)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.top, 48 + insets.top)
                    .padding(.leading, 40 + insets.leading)
                    .padding(.trailing, 40 + insets.trailing)
                    .padding(.bottom, 64 + insets.bottom)
                Text("\(pageNumber)")
                    .font(Theme.storyFont(size: 15))
                    .foregroundStyle(Theme.softInk)
                    .padding(.bottom, 24 + insets.bottom)
            }
        }
    }
}

/// Reads the fold (`.division`) and camera (`.occlusion`) regions for a pane and turns them into padding.
enum ReservedRegionInsets {
    static func insets(for proxy: GeometryProxy) -> SafeInsets {
        let regions = proxy.reservedRegions(kind: .division, options: []) + proxy.reservedRegions(kind: .occlusion, options: [])
        return SafeInsets.avoiding(regions.map(\.frame), in: proxy.size)
    }
}
