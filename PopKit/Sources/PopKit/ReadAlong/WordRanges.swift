import Foundation

/// Splits a page's text into per-word ranges for read-along highlighting, and maps
/// `AVSpeechSynthesizerDelegate`'s `willSpeakRange(_:utterance:)` callback (an
/// `NSRange` into the utterance's string) to the word it falls within. Pure
/// `NSString`/`NSRange` logic, so it's testable without AVFoundation.
public enum WordRanges {
    /// Every word's `NSRange` in `text`, in reading order. Uses ICU word breaking
    /// (`.byWords`), so trailing punctuation isn't part of the word's range and
    /// contractions like "don't" stay one word.
    public static func words(in text: String) -> [NSRange] {
        let nsText = text as NSString
        guard nsText.length > 0 else { return [] }

        var ranges: [NSRange] = []
        nsText.enumerateSubstrings(in: NSRange(location: 0, length: nsText.length), options: [.byWords, .substringNotRequired]) { _, range, _, _ in
            ranges.append(range)
        }
        return ranges
    }

    /// The index into `words` for the word `spokenRange` falls within. A range
    /// nested entirely inside a word (some voices call back per syllable) maps to
    /// that same word. A location that falls between words (on punctuation or
    /// whitespace) maps to the next word. Returns `nil` once `spokenRange` is at or
    /// past the end of the text, or `words` is empty.
    public static func wordIndex(for spokenRange: NSRange, in words: [NSRange]) -> Int? {
        for (index, word) in words.enumerated() {
            if NSLocationInRange(spokenRange.location, word) {
                return index
            }
            if spokenRange.location < word.location {
                return index
            }
        }
        return nil
    }
}
