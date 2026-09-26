import Foundation
import Testing
@testable import PopKit

/// Covers `DialogueSegments`: splitting page text into narration and quoted-dialogue
/// segments for talking-characters read-along (ROADMAP Phase 8.4), each carrying its
/// range in the original text so word-highlighting keeps working across voice switches.
struct DialogueSegmentsTests {
    private func text(of segment: DialogueSegment, in original: String) -> String {
        (original as NSString).substring(with: segment.range)
    }

    @Test func emptyTextHasNoSegments() {
        #expect(DialogueSegments.segments(in: "").isEmpty)
    }

    @Test func plainNarrationIsOneSegment() {
        let text = "Pip walked through the meadow."
        let segments = DialogueSegments.segments(in: text)
        #expect(segments.count == 1)
        #expect(segments[0].kind == .narration)
        #expect(segments[0].text == text)
        #expect(segments[0].range == NSRange(location: 0, length: (text as NSString).length))
    }

    @Test func quotedDialogueInTheMiddleSplitsIntoThreeSegments() {
        let text = #"Pip stopped. "Where am I?" she wondered."#
        let segments = DialogueSegments.segments(in: text)
        #expect(segments.map(\.kind) == [.narration, .dialogue, .narration])
        #expect(segments[1].text == "\"Where am I?\"")
        for segment in segments {
            #expect(self.text(of: segment, in: text) == segment.text)
        }
    }

    @Test func leadingDialogueHasNoEmptyNarrationSegmentBefore() {
        let text = #""Hello!" said the fox."#
        let segments = DialogueSegments.segments(in: text)
        #expect(segments.first?.kind == .dialogue)
        #expect(segments.first?.range.location == 0)
    }

    @Test func trailingDialogueHasNoEmptyNarrationSegmentAfter() {
        let text = #"The fox smiled. "Goodbye!""#
        let segments = DialogueSegments.segments(in: text)
        #expect(segments.last?.kind == .dialogue)
        let nsText = text as NSString
        #expect(segments.last?.range.location.advanced(by: segments.last?.range.length ?? 0) == nsText.length)
    }

    @Test func multipleQuotesEachBecomeTheirOwnSegment() {
        let text = #""Hi!" said Pip. "Bye!" said Rex."#
        let segments = DialogueSegments.segments(in: text)
        #expect(segments.filter { $0.kind == .dialogue }.map(\.text) == ["\"Hi!\"", "\"Bye!\""])
    }

    @Test func curlyQuotesAreRecognisedAsDialogue() {
        let text = "Pip said, “I found it!” and smiled."
        let segments = DialogueSegments.segments(in: text)
        #expect(segments.contains { $0.kind == .dialogue && $0.text == "“I found it!”" })
    }

    @Test func anUnterminatedQuoteBecomesDialogueToTheEnd() {
        let text = #"Pip said, "I'm not sure"#
        let segments = DialogueSegments.segments(in: text)
        #expect(segments.last?.kind == .dialogue)
    }

    @Test func segmentsCoverTheWholeTextWithNoGapsOrOverlaps() {
        let text = #"Once, "Look!" cried Pip, and then "Wow" echoed Rex, softly."#
        let segments = DialogueSegments.segments(in: text)
        let reassembled = segments.map(\.text).joined()
        #expect(reassembled == text)
        var cursor = 0
        for segment in segments {
            #expect(segment.range.location == cursor)
            cursor += segment.range.length
        }
        #expect(cursor == (text as NSString).length)
    }
}
