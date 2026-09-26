import AVFoundation
import Observation
import PopKit

/// Read-along (ROADMAP Phase 8.1, 8.4): Apple's on-device voice reads the page and reports
/// the word it's saying, so the text page can highlight it. OpenAI speech has no word
/// timings, so this is the only voice used for reading (ROADMAP §3). Quoted dialogue is
/// split out (`DialogueSegments`) and spoken with a different voice, pitch and rate from
/// narration — talking characters (ROADMAP Phase 8.4) — while highlighting keeps tracking
/// the right word by mapping each segment's own spoken range back onto the full page text.
@MainActor
@Observable
final class ReadAloud: NSObject {
    /// The range of the word being spoken, in the full text passed to `read(_:)`.
    private(set) var spokenRange: NSRange?
    private(set) var isReading = false

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var segments: [DialogueSegment] = []
    @ObservationIgnored private var currentSegmentIndex = 0

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Reads `text` from the start; any reading in progress stops first. Each dialogue
    /// segment is its own utterance, queued in order, so the synthesizer plays them back
    /// to back with no gap other than each utterance's own trailing pause.
    func read(_ text: String, language: String = "en-US", rate: Float = 0.42) {
        stop()
        guard !text.isEmpty else { return }
        segments = DialogueSegments.segments(in: text)
        currentSegmentIndex = 0
        isReading = true
        for segment in segments {
            synthesizer.speak(Self.utterance(for: segment, language: language, narrationRate: rate))
        }
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        reset()
    }

    private static func utterance(for segment: DialogueSegment, language: String, narrationRate: Float) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: segment.text)
        utterance.postUtteranceDelay = 0.2
        switch segment.kind {
        case .narration:
            utterance.voice = AVSpeechSynthesisVoice(language: language)
            utterance.rate = narrationRate
            utterance.pitchMultiplier = 1.08
        case .dialogue:
            utterance.voice = dialogueVoice(language: language)
            utterance.rate = min(narrationRate * 1.08, AVSpeechUtteranceMaximumSpeechRate)
            utterance.pitchMultiplier = 1.35
        }
        return utterance
    }

    /// A different on-device voice for quoted dialogue when this language has more than
    /// one installed; otherwise the same voice, still set apart by pitch and rate.
    private static func dialogueVoice(language: String) -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == language }
        let narrator = AVSpeechSynthesisVoice(language: language)
        return voices.first { $0.identifier != narrator?.identifier } ?? narrator
    }

    /// Maps the utterance-relative range `willSpeakRange` reports onto the current
    /// segment's place in the full page text.
    private func willSpeak(_ range: NSRange) {
        guard segments.indices.contains(currentSegmentIndex) else { return }
        let segment = segments[currentSegmentIndex]
        spokenRange = NSRange(location: segment.range.location + range.location, length: range.length)
    }

    /// One queued utterance finished; the next one (if any) is about to start speaking.
    private func advancedPastCurrentSegment() {
        currentSegmentIndex += 1
        if currentSegmentIndex >= segments.count { reset() }
    }

    private func reset() {
        isReading = false
        spokenRange = nil
        segments = []
        currentSegmentIndex = 0
    }
}

extension ReadAloud: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        Task { @MainActor in self.willSpeak(characterRange) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.advancedPastCurrentSegment() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.reset() }
    }
}

enum HighlightedText {
    /// The page text with the spoken word marked in the accent colour and underlined.
    static func attributed(_ text: String, highlight range: NSRange?) -> AttributedString {
        var result = AttributedString(text)
        guard let range, let swiftRange = Range(range, in: text),
              let lower = AttributedString.Index(swiftRange.lowerBound, within: result),
              let upper = AttributedString.Index(swiftRange.upperBound, within: result)
        else { return result }
        result[lower..<upper].foregroundColor = Theme.accent
        result[lower..<upper].underlineStyle = .single
        return result
    }
}
