@preconcurrency import AVFoundation
import PopKit
import Speech

/// Fallback speech-to-text with Apple's recogniser, used when Realtime can't start (no
/// network, or the `stt-token` function fails). Utterances end after a short pause.
/// Recogniser errors (for example "no speech detected" after a quiet spell) just start a fresh
/// request; only errors that repeat straight away stop listening.
@MainActor
final class AppleTranscriber: SpeechInput {
    let updates: AsyncStream<SpeechUpdate>
    private let sink: AsyncStream<SpeechUpdate>.Continuation
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// Callbacks from a request that was ended or replaced are ignored.
    private var generation = 0
    private var requestStarted = ContinuousClock.now
    private var quickFailures = 0
    private var pauseTimer: Task<Void, Never>?
    private var utterance: String?
    private var utteranceCount = 0
    /// Keeps utterance ids unique across transcribers (the speaker ledger outlives this one).
    private let idPrefix = "apple-\(UUID().uuidString.prefix(8))"
    private var latest = ""
    private var isRunning = false
    private static let pause = Duration.milliseconds(1_400)
    /// An error sooner than this after a request starts counts as a quick failure.
    private static let quickFailure = Duration.seconds(1)
    private static let maxQuickFailures = 3

    init() {
        (updates, sink) = AsyncStream.makeStream(of: SpeechUpdate.self, bufferingPolicy: .unbounded)
    }

    func start() async throws {
        guard !isRunning else { return }
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized, let recognizer, recognizer.isAvailable else { throw SpeechError.recognizerUnavailable }
        guard await MicrophoneStream.requestPermission() else { throw SpeechError.microphoneDenied }
        try MicrophoneStream.activateSession()
        isRunning = true
        do {
            try begin(with: recognizer)
        } catch {
            isRunning = false
            endRequest()
            MicrophoneStream.deactivateSession()
            throw error
        }
    }

    func stop(waitingForWords: Bool) async {
        guard isRunning else { return }
        isRunning = false
        pauseTimer?.cancel()
        endRequest()
        if waitingForWords { flush() }
        MicrophoneStream.deactivateSession()
        sink.finish()
    }

    func endUtterance() {
        guard isRunning, utterance != nil else { return }
        restart()
    }

    private func begin(with recognizer: SFSpeechRecognizer) throws {
        generation += 1
        let current = generation
        requestStarted = .now
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        self.request = request
        let input = engine.inputNode
        // No input route yet (it happens in the simulator): installing a tap would crash.
        guard input.outputFormat(forBus: 0).sampleRate > 0 else { throw SpeechError.audioFormat }
        input.installTap(onBus: 0, bufferSize: 1_024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        try engine.start()
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let failure = error?.localizedDescription
            Task { @MainActor in self?.receive(text: text, error: failure, generation: current) }
        }
    }

    private func receive(text: String?, error: String?, generation: Int) {
        guard isRunning, generation == self.generation else { return }
        if let text, !text.isEmpty {
            quickFailures = 0
            if utterance == nil {
                utteranceCount += 1
                let id = "\(idPrefix)-\(utteranceCount)"
                utterance = id
                sink.yield(.began(utterance: id))
            }
            latest = text
            sink.yield(.partial(text))
            schedulePauseCheck()
        } else if let error {
            quickFailures = requestStarted.duration(to: .now) < Self.quickFailure ? quickFailures + 1 : 0
            if quickFailures >= Self.maxQuickFailures {
                fail("Listening stopped: \(error)")
            } else {
                restart()
            }
        }
    }

    /// Apple's recogniser keeps one long transcript; a pause ends the utterance.
    private func schedulePauseCheck() {
        pauseTimer?.cancel()
        pauseTimer = Task { [weak self] in
            do { try await Task.sleep(for: Self.pause) } catch { return }
            self?.restart()
        }
    }

    /// Ends the utterance so far and listens again with a fresh request.
    private func restart() {
        guard isRunning, let recognizer else { return }
        pauseTimer?.cancel()
        flush()
        endRequest()
        do {
            try begin(with: recognizer)
        } catch {
            fail("Listening stopped: \(error.localizedDescription)")
        }
    }

    private func endRequest() {
        generation += 1
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
    }

    private func flush() {
        let text = latest.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = utterance
        latest = ""
        utterance = nil
        guard !text.isEmpty else { return }
        sink.yield(.final(text, utterance: id))
        sink.yield(.partial(""))
    }

    private func fail(_ message: String) {
        flush()
        sink.yield(.failed(message))
        isRunning = false
        pauseTimer?.cancel()
        endRequest()
        MicrophoneStream.deactivateSession()
        sink.finish()
    }
}
