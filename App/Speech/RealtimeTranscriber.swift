import Foundation

/// Speech-to-text through OpenAI Realtime in transcription-only mode (ROADMAP §3, PRD S1).
/// The app never holds the API key: `fetchSecret` asks the `stt-token` function for a
/// short-lived client secret. Microphone audio streams straight to OpenAI and is never stored.
@MainActor
final class RealtimeTranscriber: SpeechInput {
    struct Secret: Sendable {
        let value: String
        let model: String
    }

    let updates: AsyncStream<SpeechUpdate>
    private let sink: AsyncStream<SpeechUpdate>.Continuation
    private let fetchSecret: @Sendable () async throws -> Secret
    private let microphone = MicrophoneStream(sampleRate: 24_000)
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var partial = ""

    static let endpoint = URL(string: "wss://api.openai.com/v1/realtime")!

    init(fetchSecret: @escaping @Sendable () async throws -> Secret) {
        self.fetchSecret = fetchSecret
        (updates, sink) = AsyncStream.makeStream(of: SpeechUpdate.self, bufferingPolicy: .bufferingNewest(64))
    }

    func start() async throws {
        guard socket == nil else { return }
        guard await MicrophoneStream.requestPermission() else { throw SpeechError.microphoneDenied }
        let secret = try await fetchSecret()
        var request = URLRequest(url: Self.endpoint)
        request.setValue("Bearer \(secret.value)", forHTTPHeaderField: "Authorization")
        let socket = URLSession.shared.webSocketTask(with: request)
        self.socket = socket
        socket.resume()
        receiveTask = Task { [weak self] in await self?.receiveLoop(socket) }
        try microphone.start { [weak socket] pcm in
            let event: [String: Any] = ["type": "input_audio_buffer.append", "audio": pcm.base64EncodedString()]
            guard let socket, let data = try? JSONSerialization.data(withJSONObject: event),
                  let text = String(data: data, encoding: .utf8) else { return }
            socket.send(.string(text)) { _ in }
        }
    }

    func stop() async {
        microphone.stop()
        receiveTask?.cancel()
        receiveTask = nil
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        if !partial.isEmpty {
            sink.yield(.final(partial))
            partial = ""
        }
    }

    private func receiveLoop(_ socket: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await socket.receive()
                guard case let .string(text) = message else { continue }
                handle(text)
            } catch {
                if !Task.isCancelled, self.socket != nil {
                    sink.yield(.failed("Listening stopped: \(error.localizedDescription)"))
                }
                return
            }
        }
    }

    /// Transcription events use the same names in the beta and GA Realtime APIs.
    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = event["type"] as? String
        else { return }
        switch type {
        case "conversation.item.input_audio_transcription.delta":
            partial += event["delta"] as? String ?? ""
            sink.yield(.partial(partial))
        case "conversation.item.input_audio_transcription.completed":
            let transcript = (event["transcript"] as? String ?? partial).trimmingCharacters(in: .whitespacesAndNewlines)
            partial = ""
            if !transcript.isEmpty { sink.yield(.final(transcript)) }
        case "error":
            let detail = (event["error"] as? [String: Any])?["message"] as? String ?? "unknown error"
            sink.yield(.failed("Listening failed: \(detail)"))
        default:
            break
        }
    }
}
