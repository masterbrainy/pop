import PopKit
import SwiftUI

/// The left page: the story text at the kid's reading level (PRD P1), padded clear of the
/// fold and camera.
struct TextPageView: View {
    let text: String
    let level: ReadingLevel
    let pageNumber: Int
    /// The word read-along is saying right now.
    var highlight: NSRange? = nil
    var placeholder = "Tell the story, and the words appear here."

    private var fontSize: Double { level.minimumTextSize + 4 }

    var body: some View {
        GeometryReader { proxy in
            let insets = ReservedRegionInsets.insets(for: proxy)
            // The closed Duo's outer screen gives each page half of 466×678 pt; there the
            // text shrinks further and the margins tighten so the whole page still fits.
            let compact = proxy.size.height < 420
            ZStack(alignment: .bottom) {
                Theme.paper
                Text(text.isEmpty ? AttributedString(placeholder) : HighlightedText.attributed(text, highlight: highlight))
                    .font(Theme.storyFont(size: compact ? fontSize * 0.8 : fontSize))
                    .foregroundStyle(text.isEmpty ? Theme.softInk : Theme.ink)
                    .lineSpacing(fontSize * (compact ? 0.12 : 0.25))
                    // P1: never smaller than the level's minimum size on the open book.
                    .minimumScaleFactor(compact ? 0.5 : level.minimumTextSize / fontSize)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: compact ? .topLeading : .leading)
                    .padding(.top, (compact ? 64 : 48) + insets.top)
                    .padding(.leading, (compact ? 24 : 40) + insets.leading)
                    .padding(.trailing, (compact ? 24 : 40) + insets.trailing)
                    .padding(.bottom, (compact ? 36 : 64) + insets.bottom)
                Text("\(pageNumber)")
                    .font(Theme.storyFont(size: compact ? 12 : 15))
                    .foregroundStyle(Theme.softInk)
                    .padding(.bottom, (compact ? 10 : 24) + insets.bottom)
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
