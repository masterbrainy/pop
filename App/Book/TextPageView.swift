import PopKit
import SwiftUI

/// The left page: the story text at the kid's reading level (PRD P1), padded clear of the
/// fold and camera, over a faint echo of the page's own illustration in its colours.
struct TextPageView: View {
    let text: String
    let level: ReadingLevel
    let pageNumber: Int
    /// The word read-along is saying right now.
    var highlight: NSRange? = nil
    var placeholder = "Tell the story, and the words appear here."
    /// The co-pilot strip's question for the parent to ask (PRD C3); shown while reading.
    var question: String? = nil
    /// The page's illustration, echoed faintly behind the words.
    var backdrop: UIImage? = nil
    /// Caches the backdrop's colours; the still's path.
    var backdropKey: String? = nil

    private var fontSize: Double { level.minimumTextSize + 4 }

    var body: some View {
        GeometryReader { proxy in
            let insets = ReservedRegionInsets.insets(for: proxy)
            // The closed Duo's outer screen gives each page half of 466×678 pt; there the
            // text shrinks further and the margins tighten so the whole page still fits.
            let compact = proxy.size.height < 420
            let palette = PagePalette.of(backdrop, key: backdropKey)
            ZStack(alignment: .bottom) {
                TextPageBackdrop(image: backdrop, palette: palette)
                Text(text.isEmpty ? AttributedString(placeholder) : HighlightedText.attributed(text, highlight: highlight))
                    .font(Theme.storyFont(size: compact ? fontSize * 0.8 : fontSize))
                    .foregroundStyle(text.isEmpty ? Theme.softInk : palette.ink)
                    .lineSpacing(fontSize * (compact ? 0.12 : 0.25))
                    // P1: never smaller than the level's minimum size on the open book.
                    .minimumScaleFactor(compact ? 0.5 : level.minimumTextSize / fontSize)
                    // Words sit high on clear paper; the picture's echo fills the bottom.
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, (compact ? 64 : 72) + insets.top)
                    .padding(.leading, (compact ? 24 : 40) + insets.leading)
                    .padding(.trailing, (compact ? 24 : 40) + insets.trailing)
                    .padding(.bottom, (compact ? 36 : 96) + insets.bottom)
                VStack(spacing: compact ? 6 : 12) {
                    if let question {
                        CoPilotStrip(question: question, compact: compact)
                            .padding(.leading, (compact ? 16 : 32) + insets.leading)
                            .padding(.trailing, (compact ? 16 : 32) + insets.trailing)
                    }
                    Text("\(pageNumber)")
                        .font(Theme.storyFont(size: compact ? 12 : 15))
                        .foregroundStyle(Theme.softInk)
                }
                .padding(.bottom, (compact ? 10 : 24) + insets.bottom)
            }
        }
    }
}

/// Reading together (PRD C3): one question the parent can ask about the page.
private struct CoPilotStrip: View {
    let question: String
    let compact: Bool

    var body: some View {
        Label {
            Text(question)
                .font(.system(size: compact ? 12 : 15, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, compact ? 10 : 14)
        .padding(.vertical, compact ? 6 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.paperShade, in: .rect(cornerRadius: 14))
        .accessibilityLabel("Ask: \(question)")
    }
}

/// Reads the fold (`.division`) and camera (`.occlusion`) regions for a pane and turns them into padding.
enum ReservedRegionInsets {
    static func insets(for proxy: GeometryProxy) -> SafeInsets {
        let regions = proxy.reservedRegions(kind: .division, options: []) + proxy.reservedRegions(kind: .occlusion, options: [])
        return SafeInsets.avoiding(regions.map(\.frame), in: proxy.size)
    }
}
