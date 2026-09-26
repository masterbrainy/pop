import Foundation

/// Turns OpenAI Realtime transcription events into `SpeechUpdate`s (PRD S1). Event names are
/// the same in the beta and GA APIs. Server `error` events are reported but never fatal: most
/// leave the session open, so only a closed socket stops listening. Words are kept per
/// utterance (`item_id`) until their transcript lands, so none are dropped when listening stops.
public struct RealtimeTranscript: Sendable {
    public enum Output: Sendable, Equatable {
        case update(SpeechUpdate)
        /// A server error or failed transcription, for the log.
        case serverError(String)
    }

    /// The server has sent its first event, so audio can go out.
    public private(set) var isOpen = false
    /// Utterances heard (or committed) whose transcript hasn't landed, in order.
    private var pending: [String] = []
    private var words: [String: String] = [:]
    /// The utterance the server hears being spoken right now.
    private var speaking: String?
    private var awaitingCommit = false
    /// A server id for an utterance that began under another id (a commit sent mid-speech), so
    /// its words keep the id, and the speaker, they began with.
    private var aliases: [String: String] = [:]

    public init() {}

    public var isSpeaking: Bool { speaking != nil }

    /// Nothing more is coming: the socket is open, no commit is unanswered and every
    /// utterance heard has its transcript.
    public var isSettled: Bool { isOpen && !awaitingCommit && pending.isEmpty }

    public mutating func receive(_ text: String) -> [Output] {
        guard let data = text.data(using: .utf8),
              let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = event["type"] as? String
        else { return [] }
        isOpen = true
        let item = (event["item_id"] as? String).map { aliases[$0] ?? $0 }
        switch type {
        case "input_audio_buffer.speech_started":
            guard let item else { return [] }
            speaking = item
            return track(item)
        case "input_audio_buffer.speech_stopped":
            if speaking == item { speaking = nil }
            return []
        case "input_audio_buffer.committed":
            awaitingCommit = false
            defer { speaking = nil }
            guard let item else { return [] }
            // A commit sent while speaking ends that utterance, whatever id the server gives it.
            if let spoken = speaking, spoken != item, !pending.contains(item) {
                aliases[item] = spoken
                return []
            }
            return track(item)
        case "conversation.item.input_audio_transcription.delta":
            guard let item else { return [] }
            let began = track(item)
            words[item, default: ""] += event["delta"] as? String ?? ""
            return began + [.update(.partial(partialText))]
        case "conversation.item.input_audio_transcription.completed":
            guard let item else { return [] }
            let transcript = (event["transcript"] as? String ?? words[item] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            forget(item)
            let final: [Output] = transcript.isEmpty ? [] : [.update(.final(transcript, utterance: item))]
            return final + [.update(.partial(partialText))]
        case "conversation.item.input_audio_transcription.failed":
            if let item { forget(item) }
            return [.serverError(Self.message(in: event)), .update(.partial(partialText))]
        case "error":
            // A refused commit (for example an empty buffer) answers the commit.
            awaitingCommit = false
            return [.serverError(Self.message(in: event))]
        default:
            return []
        }
    }

    /// Call after sending `commitEvent`: the transcript isn't settled until the server answers.
    public mutating func commitSent() {
        awaitingCommit = true
    }

    /// Words heard but never finished (the socket closed, or listening stopped before their
    /// transcript landed) become finals, in order, and the transcript starts over for a new
    /// socket. Empty when nothing was left.
    public mutating func takeLeftovers() -> [SpeechUpdate] {
        let finals: [SpeechUpdate] = pending.compactMap { item in
            let text = (words[item] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : .final(text, utterance: item)
        }
        let hadWords = !words.isEmpty
        self = RealtimeTranscript()
        return hadWords ? finals + [.partial("")] : finals
    }

    public static func appendEvent(_ pcm: Data) -> String {
        #"{"type":"input_audio_buffer.append","audio":"\#(pcm.base64EncodedString())"}"#
    }

    public static let commitEvent = #"{"type":"input_audio_buffer.commit"}"#

    /// Silent 24 kHz 16-bit mono audio. Sent after the mic stops, it lets the server's voice
    /// detection hear the pause that ends the last utterance, with no risk of committing
    /// silence on its own (a transcription model can invent words from silence).
    public static func silence(seconds: Double) -> Data {
        Data(count: Int(24_000 * seconds) * MemoryLayout<Int16>.size)
    }

    private var partialText: String {
        pending.compactMap { words[$0]?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private mutating func track(_ item: String) -> [Output] {
        guard !pending.contains(item) else { return [] }
        pending.append(item)
        return [.update(.began(utterance: item))]
    }

    private mutating func forget(_ item: String) {
        pending.removeAll { $0 == item }
        words[item] = nil
        if speaking == item { speaking = nil }
    }

    private static func message(in event: [String: Any]) -> String {
        (event["error"] as? [String: Any])?["message"] as? String ?? "unknown error"
    }
}

/// Microphone audio captured before the socket opens (or while it reconnects), sent the
/// moment it's open so the first words aren't lost. Past `maxBytes` the oldest audio goes.
public struct PendingAudio: Sendable {
    private var chunks: [Data] = []
    private var bytes = 0
    private let maxBytes: Int

    public init(maxBytes: Int) {
        self.maxBytes = maxBytes
    }

    public mutating func append(_ chunk: Data) {
        chunks.append(chunk)
        bytes += chunk.count
        while bytes > maxBytes, chunks.count > 1 {
            bytes -= chunks.removeFirst().count
        }
    }

    public mutating func drain() -> [Data] {
        defer {
            chunks = []
            bytes = 0
        }
        return chunks
    }
}
