import Foundation
import Testing
@testable import PopKit

/// Covers `TurnQueue` (R-31): a second input arriving while a turn is in flight
/// must queue rather than be dropped, and queued inputs merge in order when the
/// turn returns.
struct TurnQueueTests {
    private func input(_ text: String, speaker: Speaker = .parent, kind: InputKind = .typed) -> StoryTurnInput {
        StoryTurnInput(kind: kind, speaker: speaker, text: text)
    }

    @Test func firstInputReachesTheEngineImmediately() async {
        let queue = TurnQueue()
        let first = input("Once there was a little fox.")

        let toRun = await queue.submit(first)

        #expect(toRun == first)
        #expect(await queue.isBusy)
    }

    @Test func aSecondInputWhileATurnIsInFlightQueuesInsteadOfBeingDropped() async {
        let queue = TurnQueue()
        let first = input("Once there was a little fox.")
        let second = input("She loved the moon.")

        _ = await queue.submit(first)
        let immediate = await queue.submit(second)
        #expect(immediate == nil, "queued, not run immediately")

        let next = await queue.drain()

        #expect(next?.text == "She loved the moon.")
    }

    @Test func threeQueuedInputsJoinInOrderWithASpace() async {
        let queue = TurnQueue()
        _ = await queue.submit(input("Once upon a time"))
        _ = await queue.submit(input("there was a fox."))
        _ = await queue.submit(input("She found a leaf."))
        _ = await queue.submit(input("The leaf glowed."))

        let next = await queue.drain()

        #expect(next?.text == "there was a fox. She found a leaf. The leaf glowed.")
    }

    @Test func mergedInputKeepsTheSpeakerOfTheLatestQueuedInput() async {
        let queue = TurnQueue()
        _ = await queue.submit(input("Once upon a time", speaker: .parent))
        _ = await queue.submit(input("keep going", speaker: .parent))
        _ = await queue.submit(input("make it a dragon", speaker: .kid))

        let next = await queue.drain()

        #expect(next?.speaker == .kid)
        #expect(next?.text == "keep going make it a dragon")
    }

    @Test func aContinueQueuedAlongsideRealTextIsDroppedAndTheTextWins() async {
        let queue = TurnQueue()
        _ = await queue.submit(input("Once upon a time"))
        _ = await queue.submit(StoryEngine.continueInput(speaker: .parent))
        _ = await queue.submit(input("she found a leaf"))

        let next = await queue.drain()

        #expect(next?.kind == .typed)
        #expect(next?.text == "she found a leaf")
    }

    @Test func onlyContinueRequestsQueuedKeepsTheLatestOneAsIs() async {
        let queue = TurnQueue()
        _ = await queue.submit(input("Once upon a time"))
        _ = await queue.submit(StoryEngine.continueInput(speaker: .parent))
        _ = await queue.submit(StoryEngine.continueInput(speaker: .kid))

        let next = await queue.drain()

        #expect(next?.kind == .continueStory)
        #expect(next?.speaker == .kid)
        #expect(next?.text.isEmpty == true)
    }

    @Test func drainingAnEmptyQueueMarksItIdle() async {
        let queue = TurnQueue()
        _ = await queue.submit(input("Once upon a time"))

        let next = await queue.drain()

        #expect(next == nil)
        #expect(await queue.isBusy == false)
    }

    @Test func afterDrainingTheNextSubmitRunsImmediatelyAgain() async {
        let queue = TurnQueue()
        _ = await queue.submit(input("Once upon a time"))
        _ = await queue.drain()

        let toRun = await queue.submit(input("A new turn begins."))

        #expect(toRun?.text == "A new turn begins.")
    }

    @Test func resetClearsQueuedInputsAndMarksTheQueueIdle() async {
        let queue = TurnQueue()
        _ = await queue.submit(input("Once upon a time"))
        _ = await queue.submit(input("dropped by reset"))

        await queue.reset()

        #expect(await queue.isBusy == false)
        let toRun = await queue.submit(input("fresh start"))
        #expect(toRun?.text == "fresh start")
    }
}
