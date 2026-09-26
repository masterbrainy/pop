/// Scripted hinge moves for the debug panel and automated checks. The simulator's hinge
/// can only be moved by hand in DeviceHub, so these replay the same sweeps (ROADMAP §3).
public enum HingeScript {
    public enum Move: String, Sendable, CaseIterable {
        /// Fold from flat past the turn point and open flat again.
        case turn
        /// Fold from flat to 90°, hold, and open flat again (turns the page on the way down).
        case pop
        /// Fold from flat to closed and stay closed past the hold.
        case close
        /// Open from closed to flat.
        case open
    }

    /// Angles from `from` to `to` in `step`-degree steps, always including both ends.
    public static func sweep(from: Double, to: Double, step: Double = 5) -> [Double] {
        guard step > 0, from != to else { return [from] }
        let direction: Double = to > from ? 1 : -1
        let count = Int(((to - from) * direction / step).rounded(.down))
        let steps = (0...count).map { from + Double($0) * step * direction }
        return steps.last == to ? steps : steps + [to]
    }

    public static func hold(_ angle: Double, samples: Int) -> [Double] {
        Array(repeating: angle, count: max(samples, 0))
    }

    public static func angles(for move: Move) -> [Double] {
        switch move {
        case .turn: sweep(from: 180, to: 120) + sweep(from: 120, to: 180).dropFirst()
        case .pop: sweep(from: 180, to: 90) + hold(90, samples: 20) + sweep(from: 90, to: 180).dropFirst()
        case .close: sweep(from: 180, to: 0) + hold(0, samples: 30)
        case .open: sweep(from: 0, to: 180)
        }
    }

    /// Parses a launch argument such as "turn,turn,pop"; unknown moves are skipped.
    public static func parse(_ text: String) -> [Move] {
        text.split(separator: ",").compactMap { Move(rawValue: $0.trimmingCharacters(in: .whitespaces)) }
    }
}
