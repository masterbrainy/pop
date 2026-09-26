import Foundation

/// What a speech recogniser reports while the parent (or kid) tells the story (PRD S1).
enum SpeechUpdate: Sendable, Equatable {
    /// Words so far in the current utterance; replaces the previous partial.
    case partial(String)
    /// A finished utterance, ready to become a story turn.
    case final(String)
    case failed(String)
}

/// A live transcriber. Audio is never stored (PRD §10): it streams to the recogniser and is dropped.
@MainActor
protocol SpeechInput: AnyObject {
    var updates: AsyncStream<SpeechUpdate> { get }
    func start() async throws
    func stop() async
}

enum SpeechError: LocalizedError {
    case microphoneDenied
    case recognizerUnavailable
    case audioFormat

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: "Pop! needs the microphone to hear the story. You can type instead."
        case .recognizerUnavailable: "Listening isn't available right now. You can type instead."
        case .audioFormat: "The microphone's audio couldn't be read."
        }
    }
}
