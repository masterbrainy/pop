import Foundation
import Testing
@testable import PopKit

/// Covers `WordRanges`: splitting page text into word ranges, and mapping an
/// `AVSpeechSynthesizer` `willSpeakRange` callback to the word it belongs to, for
/// read-along highlighting.
struct WordRangesTests {
    @Test func splitsPlainTextIntoOneRangePerWord() {
        let text = "Pip followed the leaf"
        let words = WordRanges.words(in: text)
        let nsText = text as NSString
        #expect(words.map { nsText.substring(with: $0) } == ["Pip", "followed", "the", "leaf"])
    }

    @Test func trailingPunctuationIsNotPartOfTheWordsRange() {
        let text = "\"Achoo!\" Pip woke up."
        let words = WordRanges.words(in: text)
        let nsText = text as NSString
        #expect(words.map { nsText.substring(with: $0) } == ["Achoo", "Pip", "woke", "up"])
    }

    @Test func emptyTextHasNoWords() {
        #expect(WordRanges.words(in: "").isEmpty)
    }

    @Test func wordIndexFindsTheWordAnExactRangeFallsIn() {
        let text = "Pip followed the leaf"
        let words = WordRanges.words(in: text)
        let theRange = words[2] // "the"
        #expect(WordRanges.wordIndex(for: theRange, in: words) == 2)
    }

    @Test func wordIndexMapsARangeNestedInsideAWordToThatSameWord() {
        // Some voices call back per syllable; "followed" spans e.g. 4...12.
        let text = "Pip followed the leaf"
        let words = WordRanges.words(in: text)
        let syllable = NSRange(location: words[1].location + 2, length: 2) // inside "followed"
        #expect(WordRanges.wordIndex(for: syllable, in: words) == 1)
    }

    @Test func wordIndexOnWhitespaceOrPunctuationBetweenWordsMapsToTheNextWord() {
        let text = "Pip, the fox"
        let words = WordRanges.words(in: text) // "Pip", "the", "fox"
        let commaLocation = words[0].location + words[0].length // right after "Pip", on the comma
        #expect(WordRanges.wordIndex(for: NSRange(location: commaLocation, length: 1), in: words) == 1)
    }

    @Test func wordIndexPastTheLastWordReturnsNil() {
        let text = "Pip ran"
        let words = WordRanges.words(in: text)
        let pastEnd = NSRange(location: (text as NSString).length, length: 0)
        #expect(WordRanges.wordIndex(for: pastEnd, in: words) == nil)
    }

    @Test func wordIndexWithNoWordsIsAlwaysNil() {
        #expect(WordRanges.wordIndex(for: NSRange(location: 0, length: 1), in: []) == nil)
    }
}
