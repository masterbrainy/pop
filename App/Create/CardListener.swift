import Foundation
import Observation
import PopKit

/// A setup card's mic (IMP-24): Apple's on-device recogniser hears one answer, then stops.
/// No server and no audio kept; what's heard only becomes a tile match or a few words.
@MainActor
@Observable
final class CardListener {
    private(set) var isListening = false
    private(set) var partial = ""

    @ObservationIgnored private var transcriber: AppleTranscriber?
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Listens for one utterance and hands its words to `onWords`; `onFailure` gets a message
    /// the parent can read if listening couldn't start or stopped.
    func listen(onWords: @escaping @MainActor (String) -> Void, onFailure: @escaping @MainActor (String) -> Void) async {
        await stop()
        let transcriber = AppleTranscriber()
        self.transcriber = transcriber
        isListening = true
        task = Task { [weak self] in
            for await update in transcriber.updates {
                guard let self, self.transcriber === transcriber else { return }
                switch update {
                case let .partial(text):
                    self.partial = text
                case let .final(text, _):
                    await self.stop()
                    onWords(text)
                    return
                case let .failed(message):
                    await self.stop()
                    onFailure(message)
                    return
                case .began:
                    break
                }
            }
        }
        do {
            try await transcriber.start()
        } catch {
            await stop()
            onFailure(error.localizedDescription)
        }
    }

    func stop() async {
        isListening = false
        partial = ""
        guard let transcriber else { return }
        self.transcriber = nil
        task?.cancel()
        task = nil
        await transcriber.stop(waitingForWords: false)
    }
}
