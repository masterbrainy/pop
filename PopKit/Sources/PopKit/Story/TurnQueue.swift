import Foundation

/// Serializes story-turn inputs so a second input arriving while a turn is in
/// flight is never lost (R-31). `submit` returns the input to run immediately
/// when no turn is running; while one is running, later inputs are queued.
/// `drain` is called when a turn finishes: it returns the next queued inputs from
/// one speaker merged into one to run next (a parent's and a kid's words are never
/// joined), or `nil` once the queue is empty (and marks the queue idle).
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
        let speaker = pending[0].speaker
        let run = Array(pending.prefix { $0.speaker == speaker })
        pending.removeFirst(run.count)
        return Self.merge(run)
    }

    /// Clears anything queued and marks the queue idle, for when the in-flight
    /// turn can't be followed by another (for example, the pipeline went away).
    public func reset() {
        pending.removeAll()
        isBusy = false
    }

    /// Joins one speaker's queued inputs in order with a space, keeping the kind
    /// of the latest one.
    private static func merge(_ inputs: [StoryTurnInput]) -> StoryTurnInput {
        let latest = inputs[inputs.count - 1]
        return StoryTurnInput(kind: latest.kind, speaker: latest.speaker, text: inputs.map(\.text).joined(separator: " "))
    }
}
