import AVFoundation
import Observation
import PopKit

/// Read-along (ROADMAP Phase 8.1, 8.4): reads the page aloud in a warm storyteller's voice and
/// reports the word being said, so the text page can highlight it and bounce the ball.
///
/// The voice is OpenAI's (the `tts` function), which sounds far more natural than the on-device
/// one. It has no word timings, so the spoken word is estimated from the audio's length, each
/// word's length and the pauses punctuation brings. Pages are fetched ahead (`prepare`) so
/// reading starts at once. When the voice can't be fetched, Apple's on-device voice reads
/// instead, with exact word timings and a second voice for quoted dialogue (Phase 8.4).
@MainActor
@Observable
final class ReadAloud: NSObject {
    /// The range of the word being spoken, in the full text passed to `read(_:)`.
    private(set) var spokenRange: NSRange?
    private(set) var isReading = false

    /// OpenAI's warm, friendly voice, and how it's asked to read.
    static let voice = "coral"
    static let instructions = "Read this children's picture-book page aloud like a warm, gentle bedtime storyteller: "
        + "unhurried, softly expressive and cosy, with a little smile in your voice and natural pauses."

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var segments: [DialogueSegment] = []
    @ObservationIgnored private var currentSegmentIndex = 0
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var tracking: Task<Void, Never>?
    @ObservationIgnored private var reading: Task<Void, Never>?
    /// Audio fetched (or being fetched) per page text.
    @ObservationIgnored private var audio: [String: Task<Data?, Never>] = [:]

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Fetches the audio for `text` in the background, so reading it later starts at once.
    func prepare(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, audio[text] == nil, let server = AppServices.shared.server else { return }
        audio[text] = Task {
            let request = TTSRequest(text: text, voice: Self.voice, instructions: Self.instructions)
            guard let response = try? await server.tts(request) else { return nil }
            return Data(base64Encoded: response.audioBase64)
        }
    }

    /// Reads `text` from the start; any reading in progress stops first.
    func read(_ text: String, language: String = "en-US") {
        stop()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isReading = true
        prepare(text)
        let pending = audio[text.trimmingCharacters(in: .whitespacesAndNewlines)]
        reading = Task { [weak self] in
            let data = await pending?.value
            guard let self, !Task.isCancelled, self.isReading else { return }
            if let data, self.play(data, for: text) { return }
            // No warm voice this time: the on-device voice reads instead.
            self.audio[text.trimmingCharacters(in: .whitespacesAndNewlines)] = nil
            self.speakOnDevice(text, language: language)
        }
    }

    func stop() {
        reading?.cancel()
        reading = nil
        tracking?.cancel()
        tracking = nil
        player?.stop()
        player = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        reset()
    }

    // MARK: - The warm voice

    /// Plays `data` and follows along with estimated word timings. False if it can't play.
    private func play(_ data: Data, for text: String) -> Bool {
        guard let player = try? AVAudioPlayer(data: data), player.duration > 0 else { return false }
        player.delegate = self
        self.player = player
        let timings = WordTimings(text: text, duration: player.duration)
        guard player.play() else { return false }
        tracking = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let player = self.player else { return }
                let range = timings.word(at: player.currentTime)
                if range != self.spokenRange { self.spokenRange = range }
                try? await Task.sleep(for: .milliseconds(40))
            }
        }
        return true
    }

    private func finishedPlaying() {
        tracking?.cancel()
        tracking = nil
        player = nil
        reset()
    }

    // MARK: - The on-device voice (fallback)

    /// Each dialogue segment is its own utterance, queued in order, so the synthesizer plays
    /// them back to back with no gap other than each utterance's own trailing pause.
    private func speakOnDevice(_ text: String, language: String, rate: Float = 0.42) {
        segments = DialogueSegments.segments(in: text)
        currentSegmentIndex = 0
        for segment in segments {
            synthesizer.speak(Self.utterance(for: segment, language: language, narrationRate: rate))
        }
    }

    private static func utterance(for segment: DialogueSegment, language: String, narrationRate: Float) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: segment.text)
        utterance.postUtteranceDelay = 0.2
        switch segment.kind {
        case .narration:
            utterance.voice = bestVoice(language: language)
            utterance.rate = narrationRate
            utterance.pitchMultiplier = 1.08
        case .dialogue:
            utterance.voice = dialogueVoice(language: language)
            utterance.rate = min(narrationRate * 1.08, AVSpeechUtteranceMaximumSpeechRate)
            utterance.pitchMultiplier = 1.35
        }
        return utterance
    }

    /// The most natural installed voice for this language (premium, then enhanced, then default).
    private static func bestVoice(language: String) -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == language }
        return voices.first { $0.quality == .premium } ?? voices.first { $0.quality == .enhanced }
            ?? AVSpeechSynthesisVoice(language: language)
    }

    /// A different on-device voice for quoted dialogue when this language has more than
    /// one installed; otherwise the same voice, still set apart by pitch and rate.
    private static func dialogueVoice(language: String) -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == language }
        let narrator = bestVoice(language: language)
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

extension ReadAloud: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.finishedPlaying() }
    }
}

/// When each word of a page is said in its recording, estimated from the recording's length:
/// each word takes time in proportion to its length, and punctuation adds a pause after it.
private struct WordTimings {
    private let words: [(range: NSRange, start: TimeInterval)]

    /// Silence the voice usually leaves before the first word.
    private static let leadIn: TimeInterval = 0.15

    init(text: String, duration: TimeInterval) {
        let ranges = ReadAlongText.wordRanges(in: text)
        let source = text as NSString
        let weights = ranges.map { range -> Double in
            let word = source.substring(with: range)
            let pause: Double = word.last.map { ".!?".contains($0) ? 6 : ",;:—".contains($0) ? 3 : 0 } ?? 0
            return Double(word.count) + 1 + pause
        }
        let total = max(weights.reduce(0, +), 1)
        let speaking = max(duration - Self.leadIn, 0.1)
        var start = Self.leadIn
        var words: [(NSRange, TimeInterval)] = []
        for (range, weight) in zip(ranges, weights) {
            words.append((range, start))
            start += speaking * weight / total
        }
        self.words = words
    }

    func word(at time: TimeInterval) -> NSRange? {
        words.last { $0.start <= time }?.range ?? words.first?.range
    }
}
