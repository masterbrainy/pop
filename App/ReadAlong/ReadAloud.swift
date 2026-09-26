import AVFoundation
import Observation

/// Read-along (ROADMAP Phase 8.1): Apple's on-device voice reads the page and reports the
/// word it's saying, so the text page can highlight it. OpenAI speech has no word timings,
/// so this is the only voice used for reading (ROADMAP §3).
@MainActor
@Observable
final class ReadAloud: NSObject {
    /// The range of the word being spoken in the text passed to `read(_:)`.
    private(set) var spokenRange: NSRange?
    private(set) var isReading = false

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var text = ""

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Reads `text` from the start; any reading in progress stops first.
    func read(_ text: String, language: String = "en-US", rate: Float = 0.42) {
        stop()
        guard !text.isEmpty else { return }
        self.text = text
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = rate
        utterance.pitchMultiplier = 1.08
        utterance.postUtteranceDelay = 0.2
        isReading = true
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        isReading = false
        spokenRange = nil
    }

    fileprivate func willSpeak(_ range: NSRange) { spokenRange = range }

    fileprivate func finished() {
        isReading = false
        spokenRange = nil
    }
}

extension ReadAloud: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        Task { @MainActor in self.willSpeak(characterRange) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished() }
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
