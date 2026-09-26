import Foundation
import PopKit

/// A live transcriber. Audio is never stored (PRD §10): it streams to the recogniser and is
/// dropped. `updates` finishes once the transcriber has stopped (or failed) for good.
@MainActor
protocol SpeechInput: AnyObject {
    var updates: AsyncStream<SpeechUpdate> { get }
    func start() async throws
    /// Stops the mic. With `waitingForWords`, words already spoken still arrive as finals
    /// (a few seconds at most) before `updates` finishes.
    func stop(waitingForWords: Bool) async
    /// Ends the utterance in progress, so words after this start a new one (the turn changed).
    func endUtterance()
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
