import Foundation

/// Whether a `DialogueSegment` is spoken narration or a character's quoted line
/// (ROADMAP Phase 8.4: talking characters).
public enum DialogueKind: Sendable, Equatable {
    case narration
    case dialogue
}

/// One run of a page's text, in reading order, with its range in the *original* text
/// (not the segment's own string) so callers can map a spoken-word offset back to the
/// full page for highlighting, even after splitting it into several utterances.
public struct DialogueSegment: Sendable, Equatable {
    public let kind: DialogueKind
    public let range: NSRange
    public let text: String

    public init(kind: DialogueKind, range: NSRange, text: String) {
        self.kind = kind
        self.range = range
        self.text = text
    }
}

/// Splits page text into narration and quoted-dialogue segments, so read-along (`ReadAloud`)
/// can speak each with a different voice, pitch or rate while keeping word highlighting
/// working: every character of the original text belongs to exactly one segment, in order,
/// so an utterance-relative spoken range plus its segment's offset always lands back on the
/// right word. Pure `NSString`/`NSRange` logic, so it's testable without AVFoundation.
public enum DialogueSegments {
    private static let openQuotes = CharacterSet(charactersIn: "\"“")
    private static let closeQuotes = CharacterSet(charactersIn: "\"”")

    /// `text`'s narration and quoted-dialogue segments, in reading order. A `"…"` or `“…”`
    /// run (quotes included, so the voice reads the whole line) is `.dialogue`; everything
    /// between them is `.narration`. An unterminated quote runs to the end of the text.
    public static func segments(in text: String) -> [DialogueSegment] {
        let nsText = text as NSString
        guard nsText.length > 0 else { return [] }

        var segments: [DialogueSegment] = []
        var cursor = 0
        var narrationStart = 0

        func flushNarration(upTo end: Int) {
            guard end > narrationStart else { return }
            let range = NSRange(location: narrationStart, length: end - narrationStart)
            segments.append(DialogueSegment(kind: .narration, range: range, text: nsText.substring(with: range)))
        }

        while cursor < nsText.length {
            guard isOpenQuote(nsText.character(at: cursor)) else {
                cursor += 1
                continue
            }
            flushNarration(upTo: cursor)

            var end = cursor + 1
            while end < nsText.length, !isCloseQuote(nsText.character(at: end)) {
                end += 1
            }
            let dialogueEnd = end < nsText.length ? end + 1 : nsText.length
            let range = NSRange(location: cursor, length: dialogueEnd - cursor)
            segments.append(DialogueSegment(kind: .dialogue, range: range, text: nsText.substring(with: range)))

            cursor = dialogueEnd
            narrationStart = cursor
        }
        flushNarration(upTo: nsText.length)
        return segments
    }

    private static func isOpenQuote(_ unit: unichar) -> Bool {
        Unicode.Scalar(unit).map(openQuotes.contains) ?? false
    }

    private static func isCloseQuote(_ unit: unichar) -> Bool {
        Unicode.Scalar(unit).map(closeQuotes.contains) ?? false
    }
}
