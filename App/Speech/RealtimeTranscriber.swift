import Foundation
import PopKit

/// Speech-to-text through OpenAI Realtime in transcription-only mode (ROADMAP §3, PRD S1).
/// The app never holds the API key: `secrets` hands out short-lived client secrets from the
/// `stt-token` function, minted ahead of the tap. Microphone audio streams straight to OpenAI
/// and is never stored.
///
/// The same audio goes to two sessions, so it can be both live and accurate:
/// - the **preview** lane commits the audio every `chunkInterval` while someone talks, so words
///   show within a second or two. Those short pieces are transcribed without the rest of the
///   sentence, so they're only ever shown, never acted on.
/// - the **main** lane lets the server's voice detection end each utterance at a real pause
///   and transcribes it whole, with a prompt naming the story's people. Only its finals go
///   to the story; each replaces the preview text for what was said.
///
/// The mic starts before the sockets open; audio waits in each lane's backlog and goes out the
/// moment it opens, so the first words aren't lost. A closed socket reconnects once, silently,
/// with a fresh secret; a second failure of the main lane stops listening (the preview lane
/// just goes quiet).
@MainActor
final class RealtimeTranscriber: SpeechInput {
    struct Secret: Sendable {
        let value: String
        let model: String
        let expiresAt: Date
    }

    let updates: AsyncStream<SpeechUpdate>
    private let sink: AsyncStream<SpeechUpdate>.Continuation
    private let microphone = MicrophoneStream(sampleRate: 24_000)
    private var main: RealtimeLane!
    private var preview: RealtimeLane!
    private var audioTask: Task<Void, Never>?
    private var audioSink: AsyncStream<Data>.Continuation?
    private var isRunning = false
    private var isStopping = false
    /// Preview pieces finished so far for what's being said now, and the piece in progress.
    private var previewDone: [String] = []
    private var previewPartial = ""
    /// The main lane's words for an utterance that ended but isn't transcribed yet.
    private var mainPartial = ""

    /// Whether the main session ever opened. If not, the caller can fall back.
    var hasOpened: Bool { main.hasOpened }

    /// - Parameter vocabulary: names likely to be said (the child, the story's characters), so
    ///   they're transcribed as spelled here.
    init(secrets: OneTimeSecrets<Secret>, vocabulary: [String] = []) {
        (updates, sink) = AsyncStream.makeStream(of: SpeechUpdate.self, bufferingPolicy: .unbounded)
        let prompt = Self.prompt(vocabulary: vocabulary)
        main = RealtimeLane(name: "main", secrets: secrets, chunks: false, prompt: prompt, silenceMs: 1_000,
                            onOutput: { [weak self] in self?.mainOutput($0) },
                            onFail: { [weak self] in self?.fail($0) })
        preview = RealtimeLane(name: "preview", secrets: secrets, chunks: true, prompt: prompt, silenceMs: nil,
                               onOutput: { [weak self] in self?.previewOutput($0) },
                               onFail: { _ in AppLog.story.info("live preview stopped; the main transcript carries on") })
    }

    func start() async throws {
        guard !isRunning else { return }
        guard await MicrophoneStream.requestPermission() else { throw SpeechError.microphoneDenied }
        isRunning = true
        do {
            try startMicrophone()
            try await main.connect()
        } catch {
            shutDown()
            throw error
        }
        // The preview is a nicety: if it can't start, the main transcript still works.
        do { try await preview.connect() } catch {
            AppLog.story.info("live preview unavailable: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop(waitingForWords: Bool) async {
        guard isRunning, !isStopping else { return }
        isStopping = true
        microphone.stop()
        audioSink?.finish()
        await audioTask?.value
        preview.shutDown()
        if waitingForWords { await main.settle() }
        for update in main.takeLeftovers() {
            if case .final = update { sink.yield(update) }
        }
        shutDown()
    }

    func endUtterance() {
        main.endUtterance()
        preview.endUtterance()
    }

    // MARK: - Audio

    private func startMicrophone() throws {
        let (stream, input) = AsyncStream.makeStream(of: Data.self, bufferingPolicy: .bufferingNewest(512))
        audioSink = input
        try microphone.start { input.yield($0) }
        audioTask = Task { [weak self] in
            for await chunk in stream {
                self?.main.audio(chunk)
                self?.preview.audio(chunk)
            }
        }
    }

    // MARK: - Transcripts

    /// Accurate, whole utterances: these become story turns.
    private func mainOutput(_ output: RealtimeTranscript.Output) {
        switch output {
        case let .update(.began(utterance)):
            sink.yield(.began(utterance: utterance))
        case let .update(.partial(text)):
            mainPartial = text
            showLive()
        case let .update(.final(text, utterance)):
            // The whole utterance is in: its preview pieces are done with.
            previewDone = []
            previewPartial = ""
            sink.yield(.final(text, utterance: utterance))
            showLive()
        case .update(.failed):
            break
        case let .serverError(message):
            AppLog.story.info("realtime error, still listening: \(message, privacy: .public)")
        }
    }

    /// Quick pieces while someone talks: shown live, never acted on.
    private func previewOutput(_ output: RealtimeTranscript.Output) {
        switch output {
        case let .update(.partial(text)):
            previewPartial = text
            showLive()
        case let .update(.final(text, _)):
            previewDone.append(text)
            previewPartial = ""
            showLive()
        case .update(.began), .update(.failed), .serverError:
            break
        }
    }

    /// What shows above the input bar: the main lane's words once an utterance has ended,
    /// else the preview of what's being said.
    private func showLive() {
        let preview = (previewDone + [previewPartial]).filter { !$0.isEmpty }.joined(separator: " ")
        sink.yield(.partial(mainPartial.isEmpty ? preview : mainPartial))
    }

    private static func prompt(vocabulary: [String]) -> String {
        let names = Array(Set(vocabulary.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })).sorted()
        var text = "A parent is telling a children's picture-book story out loud, and every word is written down exactly as said."
        if !names.isEmpty { text += " Names in this story: \(names.joined(separator: ", "))." }
        return text
    }

    private func fail(_ message: String) {
        sink.yield(.failed(message))
        shutDown()
    }

    private func shutDown() {
        isRunning = false
        microphone.stop()
        audioSink?.finish()
        audioTask?.cancel()
        main.shutDown()
        preview.shutDown()
        sink.finish()
    }
}

/// One Realtime transcription session: its socket, its transcript and its reconnect.
@MainActor
private final class RealtimeLane {
    let name: String
    private let secrets: OneTimeSecrets<RealtimeTranscriber.Secret>
    /// Commits long stretches of speech every `chunkInterval` (the preview lane).
    private let chunks: Bool
    private let prompt: String
    /// The pause that ends an utterance, if not the server's default.
    private let silenceMs: Int?
    private let onOutput: (RealtimeTranscript.Output) -> Void
    private let onFail: (String) -> Void

    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var openWatch: Task<Void, Never>?
    private var chunkTask: Task<Void, Never>?
    private var transcript = RealtimeTranscript()
    /// Up to 10 s of 24 kHz 16-bit mono audio, kept until the socket opens.
    private var backlog = PendingAudio(maxBytes: 24_000 * 2 * 10)
    private var model = ""
    private var isRunning = true
    private var mayReconnect = true
    private(set) var hasOpened = false
    private var lastServerEvent = ContinuousClock.now
    private var chunkStarted = ContinuousClock.now

    static let endpoint = URL(string: "wss://api.openai.com/v1/realtime")!
    private static let openLimit = Duration.seconds(5)
    private static let drainLimit = Duration.seconds(6)
    private static let trailingSilence = 1.3
    private static let quietWindow = Duration.milliseconds(900)
    private static let chunkInterval = Duration.milliseconds(1_200)

    init(name: String, secrets: OneTimeSecrets<RealtimeTranscriber.Secret>, chunks: Bool, prompt: String, silenceMs: Int?,
         onOutput: @escaping (RealtimeTranscript.Output) -> Void, onFail: @escaping (String) -> Void) {
        self.name = name
        self.secrets = secrets
        self.chunks = chunks
        self.prompt = prompt
        self.silenceMs = silenceMs
        self.onOutput = onOutput
        self.onFail = onFail
    }

    func audio(_ chunk: Data) {
        guard isRunning else { return }
        if transcript.isOpen, socket != nil {
            send(RealtimeTranscript.appendEvent(chunk))
        } else {
            backlog.append(chunk)
        }
    }

    func endUtterance() {
        guard transcript.isOpen, transcript.isSpeaking else { return }
        send(RealtimeTranscript.commitEvent)
        transcript.commitSent()
        chunkStarted = .now
    }

    func connect() async throws {
        let secret = try await secrets.take()
        guard isRunning else { return }
        model = secret.model
        var request = URLRequest(url: Self.endpoint)
        request.setValue("Bearer \(secret.value)", forHTTPHeaderField: "Authorization")
        let socket = URLSession.shared.webSocketTask(with: request)
        self.socket = socket
        socket.resume()
        receiveTask = Task { [weak self] in await self?.receive(from: socket) }
        openWatch?.cancel()
        openWatch = Task { [weak self] in
            do { try await Task.sleep(for: Self.openLimit) } catch { return }
            self?.giveUpOpening(socket)
        }
    }

    /// Words already spoken arrive within `drainLimit`: sends silence so voice detection ends
    /// the last utterance itself, commits by hand only if it still hears speech, then waits
    /// for every transcript.
    func settle() async {
        let deadline = ContinuousClock.now.advanced(by: Self.drainLimit)
        await wait(until: deadline) { !$0.isRunning || $0.transcript.isOpen }
        guard transcript.isOpen, socket != nil else { return }
        send(RealtimeTranscript.appendEvent(RealtimeTranscript.silence(seconds: Self.trailingSilence)))
        lastServerEvent = .now
        await wait(until: deadline) { $0.socket == nil || $0.lastServerEvent.duration(to: .now) >= Self.quietWindow }
        endUtterance()
        await wait(until: deadline) { $0.socket == nil || $0.transcript.isSettled }
    }

    func takeLeftovers() -> [SpeechUpdate] {
        transcript.takeLeftovers()
    }

    func shutDown() {
        isRunning = false
        openWatch?.cancel()
        chunkTask?.cancel()
        receiveTask?.cancel()
        receiveTask = nil
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        _ = backlog.drain()
    }

    // MARK: - Socket

    private func giveUpOpening(_ stuck: URLSessionWebSocketTask) {
        guard stuck === socket, !transcript.isOpen else { return }
        AppLog.story.info("realtime \(self.name, privacy: .public) socket didn't open in time")
        stuck.cancel(with: .goingAway, reason: nil)
    }

    private func receive(from socket: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            let message: URLSessionWebSocketTask.Message
            do {
                message = try await socket.receive()
            } catch {
                await closed(socket, error: error)
                return
            }
            if case let .string(text) = message { handle(text) }
        }
    }

    private func handle(_ text: String) {
        lastServerEvent = .now
        let wasOpen = transcript.isOpen
        let wasSpeaking = transcript.isSpeaking
        for output in transcript.receive(text) { onOutput(output) }
        if !wasSpeaking, transcript.isSpeaking { chunkStarted = .now }
        guard !wasOpen, transcript.isOpen else { return }
        mayReconnect = true
        hasOpened = true
        openWatch?.cancel()
        if let update = sessionUpdate() { send(update) }
        for chunk in backlog.drain() { send(RealtimeTranscript.appendEvent(chunk)) }
        if chunks { startChunking() }
    }

    /// Tells the session what it's hearing (so names and story words come out right) and, for
    /// the main lane, to wait for a real pause before ending an utterance.
    private func sessionUpdate() -> String? {
        var input: [String: Any] = [
            "transcription": ["model": model, "language": "en", "prompt": prompt],
        ]
        if let silenceMs {
            input["turn_detection"] = ["type": "server_vad", "silence_duration_ms": silenceMs]
        }
        let event: [String: Any] = [
            "type": "session.update",
            "session": ["type": "transcription", "audio": ["input": input]],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: event) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Commits long stretches of speech in pieces, so words arrive while they're being said.
    private func startChunking() {
        chunkTask?.cancel()
        chunkTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, self.isRunning else { return }
                if self.transcript.isSpeaking, self.chunkStarted.duration(to: .now) >= Self.chunkInterval {
                    self.endUtterance()
                }
            }
        }
    }

    /// The socket closed under us: keep what was heard, then reconnect once before giving up.
    private func closed(_ closed: URLSessionWebSocketTask, error: any Error) async {
        guard isRunning, closed === socket else { return }
        socket = nil
        receiveTask = nil
        chunkTask?.cancel()
        for update in transcript.takeLeftovers() { onOutput(.update(update)) }
        guard mayReconnect else {
            isRunning = false
            onFail("Listening stopped: \(error.localizedDescription)")
            return
        }
        mayReconnect = false
        AppLog.story.info("realtime \(self.name, privacy: .public) socket closed (\(error.localizedDescription, privacy: .public)); reconnecting once")
        do {
            try await connect()
        } catch {
            isRunning = false
            onFail("Listening stopped: \(error.localizedDescription)")
        }
    }

    private func send(_ text: String) {
        socket?.send(.string(text)) { _ in }
    }

    private func wait(until deadline: ContinuousClock.Instant, for done: (RealtimeLane) -> Bool) async {
        while !done(self), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}
