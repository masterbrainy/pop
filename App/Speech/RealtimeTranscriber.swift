import Foundation
import PopKit

/// Speech-to-text through OpenAI Realtime in transcription-only mode (ROADMAP §3, PRD S1), the
/// fallback when Apple's on-device recogniser can't start. The server only transcribes audio
/// once it's committed, so while someone keeps talking the audio so far is committed every
/// `chunkInterval`: words show within a second or two instead of only after a pause. Each
/// chunk comes back as its own final; the story maker joins them until the speaker pauses.
/// The app never holds the API key: `secrets` hands out short-lived client secrets from the
/// `stt-token` function, minted ahead of the tap. Microphone audio streams straight to OpenAI
/// and is never stored.
///
/// The mic starts before the socket opens; audio waits in `backlog` and goes out the moment it
/// opens, so the first words aren't lost. Server `error` events are logged, not fatal. A closed
/// socket (or one that doesn't open within `openLimit`) reconnects once, silently, with a fresh
/// secret; only a second failure stops listening.
@MainActor
final class RealtimeTranscriber: SpeechInput {
    struct Secret: Sendable {
        let value: String
        let model: String
        let expiresAt: Date
    }

    let updates: AsyncStream<SpeechUpdate>
    private let sink: AsyncStream<SpeechUpdate>.Continuation
    private let secrets: OneTimeSecrets<Secret>
    private let microphone = MicrophoneStream(sampleRate: 24_000)
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var openWatch: Task<Void, Never>?
    private var audioTask: Task<Void, Never>?
    private var audioSink: AsyncStream<Data>.Continuation?
    private var transcript = RealtimeTranscript()
    /// Up to 10 s of 24 kHz 16-bit mono audio, kept until the socket opens.
    private var backlog = PendingAudio(maxBytes: 24_000 * 2 * 10)
    private var isRunning = false
    private var isStopping = false
    /// One silent reconnect: spent when a socket closes, earned back once a new one opens.
    private var mayReconnect = true
    /// A socket has opened at least once. If none ever does, the caller can fall back.
    private(set) var hasOpened = false
    private var lastServerEvent = ContinuousClock.now
    /// When speech started, or the last chunk was committed.
    private var chunkStarted = ContinuousClock.now
    private var chunkTask: Task<Void, Never>?

    static let endpoint = URL(string: "wss://api.openai.com/v1/realtime")!
    /// A socket that hasn't opened by then is closed and tried again.
    private static let openLimit = Duration.seconds(5)
    /// How long a stop waits for words already spoken to be transcribed.
    private static let drainLimit = Duration.seconds(5)
    /// Silence sent after the mic stops: longer than the server's 700 ms end-of-speech pause.
    private static let trailingSilence = 1.0
    /// No server events for this long after the trailing silence: voice detection is done.
    private static let quietWindow = Duration.milliseconds(800)
    /// While someone keeps talking, what they've said so far is committed this often.
    private static let chunkInterval = Duration.milliseconds(1_200)

    init(secrets: OneTimeSecrets<Secret>) {
        self.secrets = secrets
        (updates, sink) = AsyncStream.makeStream(of: SpeechUpdate.self, bufferingPolicy: .unbounded)
    }

    func start() async throws {
        guard !isRunning else { return }
        guard await MicrophoneStream.requestPermission() else { throw SpeechError.microphoneDenied }
        isRunning = true
        do {
            try startMicrophone()
            try await connect()
        } catch {
            shutDown()
            throw error
        }
    }

    func stop(waitingForWords: Bool) async {
        guard isRunning, !isStopping else { return }
        isStopping = true
        microphone.stop()
        audioSink?.finish()
        await audioTask?.value
        if waitingForWords { await settle() }
        for update in transcript.takeLeftovers() { sink.yield(update) }
        shutDown()
    }

    func endUtterance() {
        guard transcript.isOpen, transcript.isSpeaking else { return }
        send(RealtimeTranscript.commitEvent)
        transcript.commitSent()
        chunkStarted = .now
    }

    /// Commits long stretches of speech in chunks, so words arrive while they're being said.
    private func startChunking() {
        chunkTask?.cancel()
        chunkTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, !self.isStopping else { return }
                if self.transcript.isSpeaking, self.chunkStarted.duration(to: .now) >= Self.chunkInterval {
                    self.endUtterance()
                }
            }
        }
    }

    // MARK: - Audio

    private func startMicrophone() throws {
        let (stream, input) = AsyncStream.makeStream(of: Data.self, bufferingPolicy: .bufferingNewest(512))
        audioSink = input
        try microphone.start { input.yield($0) }
        audioTask = Task { [weak self] in
            for await chunk in stream { self?.audio(chunk) }
        }
    }

    private func audio(_ chunk: Data) {
        if transcript.isOpen, socket != nil {
            send(RealtimeTranscript.appendEvent(chunk))
        } else {
            backlog.append(chunk)
        }
    }

    // MARK: - Socket

    private func connect() async throws {
        let secret = try await secrets.take()
        guard isRunning else { return }
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

    /// A handshake that hangs (flaky wifi) would otherwise leave the mic on but deaf for a
    /// minute; closing it goes through `closed`, like any other failure.
    private func giveUpOpening(_ stuck: URLSessionWebSocketTask) {
        guard stuck === socket, !transcript.isOpen else { return }
        AppLog.story.info("realtime socket didn't open in time")
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
        for output in transcript.receive(text) {
            switch output {
            case let .update(update): sink.yield(update)
            case let .serverError(message): AppLog.story.info("realtime error, still listening: \(message, privacy: .public)")
            }
        }
        if !wasSpeaking, transcript.isSpeaking { chunkStarted = .now }
        guard !wasOpen, transcript.isOpen else { return }
        mayReconnect = true
        hasOpened = true
        openWatch?.cancel()
        startChunking()
        for chunk in backlog.drain() { send(RealtimeTranscript.appendEvent(chunk)) }
    }

    /// The socket closed under us: keep what was heard, then reconnect once before giving up.
    private func closed(_ closed: URLSessionWebSocketTask, error: any Error) async {
        guard isRunning, closed === socket else { return }
        socket = nil
        receiveTask = nil
        for update in transcript.takeLeftovers() { sink.yield(update) }
        guard !isStopping else { return }
        guard mayReconnect else {
            fail("Listening stopped: \(error.localizedDescription)")
            return
        }
        mayReconnect = false
        AppLog.story.info("realtime socket closed (\(error.localizedDescription, privacy: .public)); reconnecting once")
        do {
            try await connect()
        } catch {
            fail("Listening stopped: \(error.localizedDescription)")
        }
    }

    private func send(_ text: String) {
        socket?.send(.string(text)) { _ in }
    }

    // MARK: - Stopping

    /// Lets words already spoken arrive, all within `drainLimit`: waits for the socket if it's
    /// still opening (so the audio buffered meanwhile goes out), sends a second of silence so
    /// the server's voice detection ends the last utterance itself, commits it by hand only if
    /// the server still hears speech, then waits for every transcript.
    private func settle() async {
        let deadline = ContinuousClock.now.advanced(by: Self.drainLimit)
        await wait(until: deadline) { !$0.isRunning || $0.transcript.isOpen }
        guard transcript.isOpen, socket != nil else { return }
        send(RealtimeTranscript.appendEvent(RealtimeTranscript.silence(seconds: Self.trailingSilence)))
        lastServerEvent = .now
        await wait(until: deadline) { $0.socket == nil || $0.lastServerEvent.duration(to: .now) >= Self.quietWindow }
        endUtterance()
        await wait(until: deadline) { $0.socket == nil || $0.transcript.isSettled }
    }

    private func wait(until deadline: ContinuousClock.Instant, for done: (RealtimeTranscriber) -> Bool) async {
        while !done(self), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func fail(_ message: String) {
        sink.yield(.failed(message))
        shutDown()
    }

    private func shutDown() {
        isRunning = false
        openWatch?.cancel()
        chunkTask?.cancel()
        microphone.stop()
        audioSink?.finish()
        audioTask?.cancel()
        receiveTask?.cancel()
        receiveTask = nil
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        _ = backlog.drain()
        sink.finish()
    }
}
