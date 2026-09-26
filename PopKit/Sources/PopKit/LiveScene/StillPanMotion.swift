import Foundation

/// The slow pan and zoom of a page's still (the fallback living page). It rests at the
/// identity transform, because the live video is shown unscaled on top of it: when the
/// first frame arrives the still settles back to identity over the same time the video
/// fades in, so the handover has one fade and no snap. `amount` runs from 0 (identity)
/// to 1 (fully zoomed and shifted).
public struct StillPanMotion: Sendable, Equatable {
    /// One drift out and back (14 s each way).
    public static let period: TimeInterval = 28
    /// Matches the live video's fade-in in `ArtPageView`.
    public static let settleDuration: TimeInterval = 0.8
    public static let maxZoom = 0.12
    /// Leftward shift at full zoom, as a fraction of the page width.
    public static let maxShift = 0.03

    private enum Mode: Sendable, Equatable {
        case moving
        case settling(from: Double)
    }

    private let mode: Mode
    private let anchor: Date

    public static let resting = StillPanMotion(mode: .settling(from: 0), anchor: .distantPast)

    private init(mode: Mode, anchor: Date) {
        self.mode = mode
        self.anchor = anchor
    }

    public static func scale(for amount: Double) -> Double { 1 + maxZoom * amount }
    public static func offsetFraction(for amount: Double) -> Double { -maxShift * amount }

    public func amount(at now: Date) -> Double {
        let elapsed = max(0, now.timeIntervalSince(anchor))
        switch mode {
        case .moving:
            return (1 - cos(2 * .pi * elapsed / Self.period)) / 2
        case let .settling(from):
            // Dates carry ~1e-7 s of rounding, so treat "within a microsecond" as done.
            guard elapsed < Self.settleDuration - 1e-6 else { return 0 }
            let progress = elapsed / Self.settleDuration
            let eased = progress * progress * (3 - 2 * progress)
            return from * (1 - eased)
        }
    }

    /// Drifting from wherever the still is now, without a jump.
    public func moving(at now: Date) -> StillPanMotion {
        let current = min(1, max(0, amount(at: now)))
        let phase = acos(1 - 2 * current) / (2 * .pi) // 0…0.5 of a period
        return StillPanMotion(mode: .moving, anchor: now.addingTimeInterval(-phase * Self.period))
    }

    /// Easing back to identity from wherever the still is now.
    public func settling(at now: Date) -> StillPanMotion {
        StillPanMotion(mode: .settling(from: amount(at: now)), anchor: now)
    }

    /// Resting at identity, so the view can stop redrawing.
    public func isSettled(at now: Date) -> Bool {
        mode != .moving && amount(at: now) == 0
    }
}
