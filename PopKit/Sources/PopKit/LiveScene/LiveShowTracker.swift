import Foundation

/// Numbers the page flows the living page starts (show a page → prepare → start → first
/// frame) and decides what a stalled one does. Only the newest flow's first frame may mark
/// a page live, and a flow whose first frame never comes (or that fails) is retried once
/// before the page settles on its still, so no page sits in "preparing" forever.
public struct LiveShowTracker: Sendable {
    public enum Recovery: Sendable, Equatable {
        /// Not the newest flow, or already live: nothing to do.
        case ignore
        /// Try the same page again as this new generation.
        case retry(generation: Int)
        /// Retries used up: keep the still until the page is shown again.
        case giveUp
    }

    public let maxRetries: Int
    public private(set) var generation = 0
    private var currentKey: String?
    private var retries = 0
    private var isLive = false

    public init(maxRetries: Int = 1) {
        self.maxRetries = maxRetries
    }

    /// A page version (`key`) is shown: returns its flow's generation.
    public mutating func begin(key: String) -> Int {
        if key != currentKey { retries = 0 }
        currentKey = key
        isLive = false
        generation += 1
        return generation
    }

    public func isCurrent(_ candidate: Int) -> Bool {
        currentKey != nil && candidate == generation
    }

    /// A first frame arrived for `generation`: true if it should mark the page live.
    public mutating func firstFrame(generation candidate: Int?) -> Bool {
        guard let candidate, isCurrent(candidate), !isLive else { return false }
        isLive = true
        retries = 0
        return true
    }

    /// Flow `generation` failed, or showed no frame in time.
    public mutating func stalled(generation candidate: Int) -> Recovery {
        guard isCurrent(candidate), !isLive else { return .ignore }
        guard retries < maxRetries else { return .giveUp }
        retries += 1
        generation += 1
        return .retry(generation: generation)
    }

    /// The page turned away (or the session ended): its flow no longer counts.
    public mutating func leave() {
        currentKey = nil
        isLive = false
        retries = 0
        generation += 1
    }
}
