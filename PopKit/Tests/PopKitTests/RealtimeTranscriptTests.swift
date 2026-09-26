import Foundation
import Testing
@testable import PopKit

/// Covers `RealtimeTranscript`: turning OpenAI Realtime transcription events into speech
/// updates. Server `error` events are logged, never fatal (they leave the session open),
/// words are kept per utterance, and nothing said is dropped when listening stops.
struct RealtimeTranscriptTests {
    private func event(_ fields: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: fields)
        return String(data: data, encoding: .utf8)!
    }

    private func started(_ id: String) -> String { event(["type": "input_audio_buffer.speech_started", "item_id": id]) }
    private func stopped(_ id: String) -> String { event(["type": "input_audio_buffer.speech_stopped", "item_id": id]) }
    private func committed(_ id: String) -> String { event(["type": "input_audio_buffer.committed", "item_id": id]) }
    private func delta(_ id: String, _ text: String) -> String {
        event(["type": "conversation.item.input_audio_transcription.delta", "item_id": id, "delta": text])
    }
    private func completed(_ id: String, _ text: String) -> String {
        event(["type": "conversation.item.input_audio_transcription.completed", "item_id": id, "transcript": text])
    }

    @Test func theFirstServerEventMeansTheSocketIsOpen() {
        var transcript = RealtimeTranscript()
        #expect(!transcript.isOpen)

        let outputs = transcript.receive(event(["type": "session.created"]))

        #expect(outputs.isEmpty)
        #expect(transcript.isOpen)
    }

    @Test func speechStartingAnnouncesANewUtterance() {
        var transcript = RealtimeTranscript()

        let outputs = transcript.receive(started("item_1"))

        #expect(outputs == [.update(.began(utterance: "item_1"))])
        #expect(transcript.isSpeaking)
    }

    @Test func deltasBuildThePartialAndCompletionGivesTheFinal() {
        var transcript = RealtimeTranscript()
        _ = transcript.receive(started("item_1"))
        _ = transcript.receive(stopped("item_1"))
        _ = transcript.receive(committed("item_1"))

        let first = transcript.receive(delta("item_1", "Make it "))
        let second = transcript.receive(delta("item_1", "snow"))
        let done = transcript.receive(completed("item_1", " Make it snow instead. "))

        #expect(first == [.update(.partial("Make it"))])
        #expect(second == [.update(.partial("Make it snow"))])
        #expect(done == [.update(.final("Make it snow instead.", utterance: "item_1")), .update(.partial(""))])
        #expect(!transcript.isSpeaking)
    }

    @Test func anErrorEventIsReportedButKeepsWhatWasHeard() {
        var transcript = RealtimeTranscript()
        _ = transcript.receive(started("item_1"))
        _ = transcript.receive(delta("item_1", "a dragon"))

        let outputs = transcript.receive(event(["type": "error", "error": ["message": "buffer too small"]]))

        #expect(outputs == [.serverError("buffer too small")])
        #expect(transcript.receive(completed("item_1", "a dragon")) == [.update(.final("a dragon", utterance: "item_1")), .update(.partial(""))])
    }

    @Test func aFailedTranscriptionDropsThatUtteranceAndClearsItsPartial() {
        var transcript = RealtimeTranscript()
        _ = transcript.receive(started("item_1"))
        _ = transcript.receive(delta("item_1", "mumble"))

        let outputs = transcript.receive(event(["type": "conversation.item.input_audio_transcription.failed", "item_id": "item_1",
                                                "error": ["message": "audio unclear"]]))

        #expect(outputs == [.serverError("audio unclear"), .update(.partial(""))])
        #expect(transcript.isSettled)
    }

    @Test func twoUtterancesInFlightKeepTheirOwnWords() {
        var transcript = RealtimeTranscript()
        _ = transcript.receive(started("a"))
        _ = transcript.receive(committed("a"))
        _ = transcript.receive(started("b"))
        _ = transcript.receive(delta("a", "Once upon a time"))
        _ = transcript.receive(delta("b", "a dragon"))

        let done = transcript.receive(completed("a", "Once upon a time."))

        #expect(done == [.update(.final("Once upon a time.", utterance: "a")), .update(.partial("a dragon"))])
    }

    @Test func anEmptyTranscriptGivesNoFinal() {
        var transcript = RealtimeTranscript()
        _ = transcript.receive(committed("item_1"))

        let outputs = transcript.receive(completed("item_1", "   "))

        #expect(outputs == [.update(.partial(""))])
    }

    @Test func aCommitIsUnsettledUntilTheServerCommitsOrRefuses() {
        var transcript = RealtimeTranscript()
        _ = transcript.receive(event(["type": "session.created"]))
        _ = transcript.receive(started("item_1"))
        #expect(!transcript.isSettled)

        transcript.commitSent()
        _ = transcript.receive(committed("item_1"))
        #expect(!transcript.isSettled, "its words are still coming")
        _ = transcript.receive(completed("item_1", "The end of the rainbow."))
        #expect(transcript.isSettled)

        transcript.commitSent()
        #expect(!transcript.isSettled)
        _ = transcript.receive(event(["type": "error", "error": ["message": "buffer too small"]]))
        #expect(transcript.isSettled)
    }

    @Test func aCommitWhileSpeakingKeepsTheUtteranceItBeganAsEvenUnderANewId() {
        var transcript = RealtimeTranscript()
        _ = transcript.receive(event(["type": "session.created"]))
        _ = transcript.receive(started("spoken"))
        transcript.commitSent()

        // No new `.began`: the words keep the speaker stamped when "spoken" began.
        let outputs = transcript.receive(committed("committed"))
        let partial = transcript.receive(delta("committed", "Hello"))
        let done = transcript.receive(completed("committed", "Hello there"))

        #expect(outputs.isEmpty)
        #expect(partial == [.update(.partial("Hello"))])
        #expect(done == [.update(.final("Hello there", utterance: "spoken")), .update(.partial(""))])
        #expect(!transcript.isSpeaking)
        #expect(transcript.isSettled)
    }

    @Test func leftoversOfARenamedUtteranceKeepTheIdItBeganAs() {
        var transcript = RealtimeTranscript()
        _ = transcript.receive(started("spoken"))
        transcript.commitSent()
        _ = transcript.receive(committed("committed"))
        _ = transcript.receive(delta("committed", "a sled"))

        #expect(transcript.takeLeftovers() == [.final("a sled", utterance: "spoken"), .partial("")])
    }

    @Test func silenceIsTheRightLengthOfZeroSamples() {
        let silence = RealtimeTranscript.silence(seconds: 1)

        #expect(silence.count == 48_000)
        #expect(silence.allSatisfy { $0 == 0 })
    }

    @Test func leftoversTurnHalfHeardWordsIntoFinalsInOrderAndReset() {
        var transcript = RealtimeTranscript()
        _ = transcript.receive(event(["type": "session.created"]))
        _ = transcript.receive(started("a"))
        _ = transcript.receive(delta("a", "the fox"))
        _ = transcript.receive(started("b"))
        _ = transcript.receive(started("c"))
        _ = transcript.receive(delta("c", " ran home "))

        let leftovers = transcript.takeLeftovers()

        #expect(leftovers == [.final("the fox", utterance: "a"), .final("ran home", utterance: "c"), .partial("")])
        #expect(!transcript.isOpen)
        #expect(!transcript.isSpeaking)
        #expect(transcript.takeLeftovers().isEmpty)
    }

    @Test func malformedOrUnknownEventsChangeNothingButOpenTheSocket() {
        var transcript = RealtimeTranscript()

        #expect(transcript.receive("not json").isEmpty)
        #expect(!transcript.isOpen)
        #expect(transcript.receive(event(["type": "rate_limits.updated"])).isEmpty)
        #expect(transcript.isOpen)
    }

    @Test func clientEventsAreRealtimeJSON() throws {
        let append = try JSONSerialization.jsonObject(with: Data(RealtimeTranscript.appendEvent(Data([1, 2, 3])).utf8)) as? [String: String]
        let commit = try JSONSerialization.jsonObject(with: Data(RealtimeTranscript.commitEvent.utf8)) as? [String: String]

        #expect(append == ["type": "input_audio_buffer.append", "audio": "AQID"])
        #expect(commit == ["type": "input_audio_buffer.commit"])
    }
}

/// Covers `PendingAudio`: microphone audio captured before the socket opens is kept, in
/// order and up to a cap, then sent the moment it opens.
struct PendingAudioTests {
    @Test func keepsChunksInOrderUntilDrained() {
        var pending = PendingAudio(maxBytes: 100)
        pending.append(Data([1]))
        pending.append(Data([2, 3]))

        #expect(pending.drain() == [Data([1]), Data([2, 3])])
        #expect(pending.drain().isEmpty)
    }

    @Test func dropsTheOldestAudioPastTheCap() {
        var pending = PendingAudio(maxBytes: 4)
        pending.append(Data([1, 1]))
        pending.append(Data([2, 2]))
        pending.append(Data([3, 3]))

        #expect(pending.drain() == [Data([2, 2]), Data([3, 3])])
    }
}
