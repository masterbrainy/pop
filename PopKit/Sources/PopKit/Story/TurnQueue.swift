import Foundation

/// Serializes story-turn inputs so a second input arriving while a turn is in
/// flight is never lost (R-31). `submit` returns the input to run immediately
/// when no turn is running; while one is running, later inputs are queued.
/// `drain` is called when a turn finishes: it returns the queued inputs merged
/// into one to run next, or `nil` once the queue is empty (and marks the queue
/// idle). A "continue" request queued alongside real text is dropped — the
/// text wins.
public actor TurnQueue {
    public private(set) var isBusy = false
    private var pending: [StoryTurnInput] = []

    public init() {}

    /// Submits an input. Returns the input to run now if the queue was idle;
    /// returns `nil` after queuing it if a turn is already in flight.
    @discardableResult
    public func submit(_ input: StoryTurnInput) -> StoryTurnInput? {
        guard !isBusy else {
            pending.append(input)
            return nil
        }
        isBusy = true
        return input
    }

    /// Called when the running turn finishes. Returns the next merged input to
    /// run if anything queued while it was running; otherwise marks the queue
    /// idle and returns `nil`.
    public func drain() -> StoryTurnInput? {
        guard !pending.isEmpty else {
            isBusy = false
            return nil
        }
        let merged = Self.merge(pending)
        pending.removeAll()
        return merged
    }

    /// Clears anything queued and marks the queue idle, for when the in-flight
    /// turn can't be followed by another (for example, the pipeline went away).
    public func reset() {
        pending.removeAll()
        isBusy = false
    }

    /// Joins queued text inputs in order with a space, keeping the speaker (and
    /// kind) of the latest one. A queued "continue" is dropped when real text is
    /// queued alongside it; if only "continue" requests are queued, the latest
    /// one is kept as-is.
    private static func merge(_ inputs: [StoryTurnInput]) -> StoryTurnInput {
        let textInputs = inputs.filter { $0.kind != .continueStory }
        guard !textInputs.isEmpty else {
            // Only "continue" requests queued: keep the latest one as-is.
            return inputs[inputs.count - 1]
        }
        let joinedText = textInputs.map(\.text).joined(separator: " ")
        let latest = textInputs[textInputs.count - 1]
        return StoryTurnInput(kind: latest.kind, speaker: latest.speaker, text: joinedText)
    }
}
