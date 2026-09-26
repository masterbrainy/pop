import SwiftUI

/// The page text for read-along: the word being spoken is highlighted, and a ball bounces
/// from word to word above it, the way a sing-along follows the words. Each word carries its
/// index as a text attribute, so the renderer can find where it sits on the page; the ball's
/// position is an animatable word index, so between two words it arcs over from one to the next.
struct ReadAlongText: View {
    let text: String
    /// The range (in `text`) of the word being spoken, or nil when nothing is being read.
    let highlight: NSRange?
    var ballSize: Double = 14

    @State private var ballIndex: Double = 0

    private var words: [NSRange] { Self.wordRanges(in: text) }

    private var spokenWord: Int? {
        guard let highlight else { return nil }
        return words.firstIndex { NSIntersectionRange($0, highlight).length > 0 || $0.location == highlight.location }
    }

    var body: some View {
        styledText
            .textRenderer(BouncingBallRenderer(ballIndex: ballIndex, showsBall: spokenWord != nil, ballSize: ballSize))
            .onChange(of: spokenWord, initial: true) { old, new in
                guard let new else { return }
                // The first word of a reading starts under the ball; later words hop to it.
                if old == nil {
                    ballIndex = Double(new)
                } else {
                    withAnimation(.easeInOut(duration: 0.24)) { ballIndex = Double(new) }
                }
            }
            .accessibilityLabel(text)
    }

    /// The text as one run per word (and the spaces between), each word tagged with its index.
    private var styledText: Text {
        let source = text as NSString
        var result = Text(verbatim: "")
        var cursor = 0
        for (index, range) in words.enumerated() {
            if range.location > cursor {
                let gap = Text(verbatim: source.substring(with: NSRange(location: cursor, length: range.location - cursor)))
                result = Text("\(result)\(gap)")
            }
            var word = Text(verbatim: source.substring(with: range)).customAttribute(WordIndex(index: index))
            if index == spokenWord {
                word = word.foregroundStyle(Theme.accent).underline()
            }
            result = Text("\(result)\(word)")
            cursor = range.location + range.length
        }
        if cursor < source.length {
            result = Text("\(result)\(Text(verbatim: source.substring(from: cursor)))")
        }
        return result
    }

    static func wordRanges(in text: String) -> [NSRange] {
        guard let regex = try? NSRegularExpression(pattern: #"\S+"#) else { return [] }
        return regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)).map(\.range)
    }
}

/// Marks a word of the page text with its index.
private struct WordIndex: TextAttribute {
    let index: Int
}

/// Draws the text, then the ball over the word at `ballIndex`. A fractional index (while the
/// ball animates) puts it between two words, raised by a hop that peaks halfway.
private struct BouncingBallRenderer: TextRenderer {
    var ballIndex: Double
    var showsBall: Bool
    var ballSize: Double

    var animatableData: Double {
        get { ballIndex }
        set { ballIndex = newValue }
    }

    /// Room above the first line for the ball and its hop.
    var displayPadding: EdgeInsets {
        EdgeInsets(top: ballSize + hopHeight + gap, leading: 0, bottom: 0, trailing: 0)
    }

    private var hopHeight: Double { ballSize * 1.4 }
    private var gap: Double { 4 }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        var wordRects: [Int: CGRect] = [:]
        for line in layout {
            for run in line {
                context.draw(run)
                guard let word = run[WordIndex.self] else { continue }
                let rect = run.typographicBounds.rect
                wordRects[word.index] = wordRects[word.index].map { $0.union(rect) } ?? rect
            }
        }
        guard showsBall, !wordRects.isEmpty else { return }

        let lower = Int(ballIndex.rounded(.down))
        let upper = Int(ballIndex.rounded(.up))
        let progress = ballIndex - Double(lower)
        guard let from = wordRects[lower] ?? wordRects[upper] else { return }
        let to = wordRects[upper] ?? from

        let x = from.midX + (to.midX - from.midX) * progress
        let top = from.minY + (to.minY - from.minY) * progress
        let hop = sin(progress * .pi) * hopHeight
        let ball = CGRect(x: x - ballSize / 2, y: top - gap - ballSize - hop, width: ballSize, height: ballSize)
        context.fill(Circle().path(in: ball), with: .color(Theme.accent))
    }
}
