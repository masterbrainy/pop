import Foundation

/// The hinge's coarse state, mirrored from SwiftUI's `DeviceHinge.Status` so this
/// logic stays platform-free and testable on the Mac.
public enum HingePosture: Sendable, Equatable {
    case closed
    case partiallyOpen
    case fullyOpen
}

/// One hinge reading. `angle` is in degrees: 0 = closed, 180 = flat (ROADMAP §3, probe 0.1).
/// `time` is monotonic seconds, used only for the close hold.
public struct HingeSample: Sendable, Equatable {
    public let posture: HingePosture
    public let angle: Double
    public let time: TimeInterval

    public init(posture: HingePosture, angle: Double, time: TimeInterval) {
        self.posture = posture
        self.angle = angle
        self.time = time
    }
}

/// The gesture model's angles (PRD §13 D1, set at G0; ROADMAP §10).
public struct PostureConfig: Sendable, Equatable {
    /// At or above this the book counts as open flat: the page settles and a turn can start.
    public let openAngle: Double
    /// Folding to this or below turns the page. Reopening to `openAngle` re-arms, so the
    /// gap between the two is the hysteresis that stops jitter turning two pages.
    public let turnAngle: Double
    /// The page now showing starts to pop up below this angle…
    public let popStartAngle: Double
    /// …and stands fully up at this angle and below.
    public let popFullAngle: Double
    /// At or below this (or when the system says closed) the book is closing.
    public let closedAngle: Double
    /// How long it must stay closed before the book is finished.
    public let closeHold: TimeInterval
    /// Once popped, the page stays up until the hinge opens this far past `popStartAngle`, so a
    /// hinge resting near it doesn't flap (R-26).
    public let popHysteresis: Double
    /// The curl only starts this far below `openAngle`, so a wobble near flat doesn't flicker it.
    public let curlDeadband: Double

    public init(openAngle: Double, turnAngle: Double, popStartAngle: Double, popFullAngle: Double, closedAngle: Double, closeHold: TimeInterval,
                popHysteresis: Double = 5, curlDeadband: Double = 3) {
        self.openAngle = openAngle
        self.turnAngle = turnAngle
        self.popStartAngle = popStartAngle
        self.popFullAngle = popFullAngle
        self.closedAngle = closedAngle
        self.closeHold = closeHold
        self.popHysteresis = popHysteresis
        self.curlDeadband = curlDeadband
    }

    public static let standard = PostureConfig(openAngle: 170, turnAngle: 140, popStartAngle: 130, popFullAngle: 90, closedAngle: 10, closeHold: 1.0)

    public var isValid: Bool {
        openAngle <= 180 && openAngle > turnAngle && turnAngle > popStartAngle
            && popStartAngle > popFullAngle && popFullAngle > closedAngle && closedAngle >= 0 && closeHold >= 0
    }
}

public enum PosturePhase: Sendable, Equatable {
    case unknown
    /// `armed` means the book has been open flat since the last turn, so folding can turn a page.
    case open(armed: Bool)
    /// `turnsOnReopen`: the fold came straight from flat, past the turn point, so opening
    /// again before the hold turns the page (the simulator reports only a fold's end points).
    case closing(since: TimeInterval, turnsOnReopen: Bool)
    case closed
}

public enum PostureEvent: Sendable, Equatable {
    /// The book is open flat with this page showing: start the page's animation.
    case pageSettled
    /// A fold passed the turn point: show the next page.
    case turnCommitted
    /// The page was lifted but opened back before the turn point.
    case turnCancelled
    /// The page now showing started to pop up.
    case popBegan
    /// The pop-up folded back into the picture.
    case popEnded
    /// Closed for the hold time: finish the book.
    case closed
    /// Opened from the cover.
    case opened
}

public struct PostureState: Sendable, Equatable {
    public let phase: PosturePhase
    /// The last angle, clamped to 0…180.
    public let angle: Double
    /// How far the page is lifted toward the turn point, 0…1.
    public let curl: Double
    /// How far the page now showing has popped up, 0…1.
    public let popDepth: Double

    public init(phase: PosturePhase, angle: Double, curl: Double, popDepth: Double) {
        self.phase = phase
        self.angle = angle
        self.curl = curl
        self.popDepth = popDepth
    }

    public static let initial = PostureState(phase: .unknown, angle: 0, curl: 0, popDepth: 0)

    /// While closing, hinge updates may stop; resend the last sample with the current time so the hold can complete.
    public var needsTick: Bool {
        if case .closing = phase { true } else { false }
    }
}

/// Turns hinge samples into page effects, one continuous motion (PRD §13 D1): from flat,
/// folding lifts the page; opening back before the turn point settles it; folding past it
/// turns the page; keep folding to about 90° and the page now showing pops up; opening
/// flat folds it back and starts its animation; closing counts only after the hold.
public struct PostureMachine: Sendable {
    public let config: PostureConfig

    public init(config: PostureConfig = .standard) {
        precondition(config.isValid, "PostureConfig angles must decrease from open to closed")
        self.config = config
    }

    public func reduce(_ state: PostureState, _ sample: HingeSample) -> (state: PostureState, events: [PostureEvent]) {
        let angle = min(max(sample.angle, 0), 180)
        let isClosed = sample.posture == .closed || angle <= config.closedAngle

        switch state.phase {
        case .unknown:
            if isClosed { return (PostureState(phase: .closed, angle: angle, curl: 0, popDepth: 0), []) }
            return reopen(at: angle, from: state, extra: [])
        case .closed:
            if isClosed { return (PostureState(phase: .closed, angle: angle, curl: 0, popDepth: 0), []) }
            return reopen(at: angle, from: state, extra: [.opened])
        case let .closing(since, turnsOnReopen):
            if isClosed {
                let held = sample.time - since >= config.closeHold
                return (PostureState(phase: held ? .closed : state.phase, angle: angle, curl: 0, popDepth: 0), held ? [.closed] : [])
            }
            // A quick close and reopen is a whole fold: the page turns, and the next one
            // settles only once the book is back at flat.
            return reopen(at: angle, from: state, extra: turnsOnReopen ? [.turnCommitted] : [])
        case let .open(armed):
            if isClosed {
                let closing = PostureState(phase: .closing(since: sample.time, turnsOnReopen: armed), angle: angle, curl: 0, popDepth: 0)
                return (closing, state.popDepth > 0 ? [.popEnded] : [])
            }
            return fold(to: angle, armed: armed, from: state)
        }
    }

    /// Opening from closed, from a close that began after a turn, or the first reading: turns
    /// a page only when `extra` says so.
    private func reopen(at angle: Double, from state: PostureState, extra: [PostureEvent]) -> (state: PostureState, events: [PostureEvent]) {
        let depth = popDepth(at: angle)
        let armed = angle >= config.openAngle
        let events = extra + (depth > 0 ? [.popBegan] : []) + (armed ? [.pageSettled] : [])
        return (PostureState(phase: .open(armed: armed), angle: angle, curl: 0, popDepth: depth), events)
    }

    private func fold(to angle: Double, armed: Bool, from state: PostureState) -> (state: PostureState, events: [PostureEvent]) {
        let turned = armed && angle <= config.turnAngle
        let rearmed = !armed && angle >= config.openAngle
        let curl = armed && !turned ? curlProgress(at: angle) : 0
        let depth = popDepth(at: angle, wasPopped: state.popDepth > 0)

        let turnEvents: [PostureEvent] = turned ? [.turnCommitted] : (armed && state.curl > 0 && curl == 0 ? [.turnCancelled] : [])
        let popEvents: [PostureEvent] = state.popDepth == 0 && depth > 0 ? [.popBegan] : (state.popDepth > 0 && depth == 0 ? [.popEnded] : [])
        let settleEvents: [PostureEvent] = rearmed ? [.pageSettled] : []

        let phase = PosturePhase.open(armed: (armed && !turned) || rearmed)
        return (PostureState(phase: phase, angle: angle, curl: curl, popDepth: depth), turnEvents + popEvents + settleEvents)
    }

    private func curlProgress(at angle: Double) -> Double {
        let start = config.openAngle - config.curlDeadband
        return clamp((start - angle) / (start - config.turnAngle))
    }

    /// While popped, a small positive depth holds the pop-up until the hinge opens past the
    /// hysteresis band.
    private func popDepth(at angle: Double, wasPopped: Bool) -> Double {
        let depth = popDepth(at: angle)
        guard wasPopped, depth == 0, angle < config.popStartAngle + config.popHysteresis else { return depth }
        return Self.heldPopDepth
    }

    /// Below anything the renderer shows; it only records that the page is still popped.
    static let heldPopDepth = 0.001

    private func popDepth(at angle: Double) -> Double {
        clamp((config.popStartAngle - angle) / (config.popStartAngle - config.popFullAngle))
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
