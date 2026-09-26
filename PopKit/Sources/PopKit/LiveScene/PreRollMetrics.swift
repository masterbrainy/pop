import Foundation

/// How well pre-animating the page behind works, per book: what each fold found on the page
/// it opened, how long from the fold until that page moved, and the Orbis session minutes
/// used. Shown on the scene debug overlay and written to the scripted run's log.
public struct PreRollMetrics: Equatable, Sendable {
    /// What the page a fold opened had.
    public enum FoldOutcome: Equatable, Sendable {
        /// Its loop was ready, so it moved at once.
        case clip
        /// It was running hidden with frames, so its video was revealed.
        case live
        /// It was running hidden without frames yet; its first frame shows it.
        case preparing
        /// Nothing was running for it; it starts from its still.
        case cold
    }

    public private(set) var folds = 0
    public private(set) var clipReadyAtFold = 0
    public private(set) var liveAtFold = 0
    public private(set) var coldAtFold = 0
    /// Fold → first moving frame (loop playing or live video shown), in ms, per fold.
    public private(set) var foldToMotionMs: [Int] = []
    public private(set) var sessionSeconds: Double = 0

    public init() {}

    public var sessionMinutes: Double { sessionSeconds / 60 }

    public var medianFoldToMotionMs: Int? {
        let sorted = foldToMotionMs.sorted()
        return sorted.isEmpty ? nil : sorted[sorted.count / 2]
    }

    public mutating func folded(to outcome: FoldOutcome) {
        folds += 1
        switch outcome {
        case .clip: clipReadyAtFold += 1
        case .live, .preparing: liveAtFold += 1
        case .cold: coldAtFold += 1
        }
    }

    public mutating func moved(afterMs ms: Int) {
        foldToMotionMs.append(max(0, ms))
    }

    public mutating func addSessionTime(seconds: Double) {
        guard seconds > 0 else { return }
        sessionSeconds += seconds
    }

    public var summary: String {
        let motion = medianFoldToMotionMs.map { String(format: "%.1f s", Double($0) / 1000) } ?? "–"
        return "folds \(folds) · loop ready \(clipReadyAtFold) · live \(liveAtFold) · cold \(coldAtFold) · fold→motion p50 \(motion) · session \(String(format: "%.1f", sessionMinutes)) min"
    }
}
