@preconcurrency import AVFoundation
import Speech

/// Fallback speech-to-text with Apple's recogniser, used when Realtime is unavailable
/// (no network, or the `stt-token` function fails). Utterances end after a short pause.
@MainActor
final class AppleTranscriber: SpeechInput {
    let updates: AsyncStream<SpeechUpdate>
    private let sink: AsyncStream<SpeechUpdate>.Continuation
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var pauseTimer: Task<Void, Never>?
    private var latest = ""
    private static let pause = Duration.milliseconds(1_400)

    init() {
        (updates, sink) = AsyncStream.makeStream(of: SpeechUpdate.self, bufferingPolicy: .bufferingNewest(64))
    }

    func start() async throws {
        guard task == nil else { return }
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized, let recognizer, recognizer.isAvailable else { throw SpeechError.recognizerUnavailable }
        guard await MicrophoneStream.requestPermission() else { throw SpeechError.microphoneDenied }
        try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement)
        try AVAudioSession.sharedInstance().setActive(true)
        try begin(with: recognizer)
    }

    func stop() async {
        pauseTimer?.cancel()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        flush()
    }

    private func begin(with recognizer: SFSpeechRecognizer) throws {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        self.request = request
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1_024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        try engine.start()
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let failure = error?.localizedDescription
            Task { @MainActor in self?.receive(text: text, error: failure) }
        }
    }

    private func receive(text: String?, error: String?) {
        if let text, !text.isEmpty {
            latest = text
            sink.yield(.partial(text))
            schedulePauseCheck()
        } else if let error, task != nil {
            sink.yield(.failed(error))
        }
    }

    /// Apple's recogniser keeps one long transcript; a pause ends the utterance.
    private func schedulePauseCheck() {
        pauseTimer?.cancel()
        pauseTimer = Task { [weak self] in
            do { try await Task.sleep(for: Self.pause) } catch { return }
            self?.restartAfterPause()
        }
    }

    private func restartAfterPause() {
        guard let recognizer else { return }
        flush()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        request?.endAudio()
        task?.cancel()
        task = nil
        try? begin(with: recognizer)
    }

    private func flush() {
        let text = latest.trimmingCharacters(in: .whitespacesAndNewlines)
        latest = ""
        if !text.isEmpty { sink.yield(.final(text)) }
    }
}
