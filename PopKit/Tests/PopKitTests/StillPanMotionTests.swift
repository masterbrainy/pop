import Foundation
import Testing
@testable import PopKit

/// Covers `StillPanMotion`, the slow pan of the still: it rests at identity (so it lines
/// up with the live video, which is shown unscaled), drifts smoothly from wherever it is,
/// and settles back to identity over the same 0.8 s as the video's crossfade.
struct StillPanMotionTests {
    private let t0 = Date(timeIntervalSince1970: 5_000)

    private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.001 }

    @Test func restingIsTheIdentityTransform() {
        let motion = StillPanMotion.resting
        #expect(motion.amount(at: t0) == 0)
        #expect(StillPanMotion.scale(for: 0) == 1)
        #expect(StillPanMotion.offsetFraction(for: 0) == 0)
        #expect(motion.isSettled(at: t0))
    }

    @Test func movingDriftsOutAndBackOverOnePeriodStartingFromRest() {
        let motion = StillPanMotion.resting.moving(at: t0)
        let half = StillPanMotion.period / 2
        #expect(near(motion.amount(at: t0), 0))
        #expect(near(motion.amount(at: t0.addingTimeInterval(half)), 1))
        #expect(near(motion.amount(at: t0.addingTimeInterval(StillPanMotion.period)), 0))
        #expect(!motion.isSettled(at: t0.addingTimeInterval(half)))
        #expect(StillPanMotion.scale(for: 1) > 1.05)
        #expect(StillPanMotion.offsetFraction(for: 1) < 0)
    }

    @Test func settlingReturnsToIdentityWithinTheCrossfade() {
        let quarter = StillPanMotion.period / 4
        let stopAt = t0.addingTimeInterval(quarter)
        let moving = StillPanMotion.resting.moving(at: t0)
        let midway = moving.amount(at: stopAt)
        let settling = moving.settling(at: stopAt)
        #expect(near(settling.amount(at: stopAt), midway)) // no jump when the video arrives
        let halfway = settling.amount(at: stopAt.addingTimeInterval(StillPanMotion.settleDuration / 2))
        #expect(halfway < midway && halfway > 0)
        let done = stopAt.addingTimeInterval(StillPanMotion.settleDuration)
        #expect(settling.amount(at: done) == 0)
        #expect(settling.isSettled(at: done))
    }

    @Test func movingAgainContinuesFromWhereTheStillIs() {
        let moving = StillPanMotion.resting.moving(at: t0)
        let stopAt = t0.addingTimeInterval(StillPanMotion.period / 3)
        let settling = moving.settling(at: stopAt)
        let resumeAt = stopAt.addingTimeInterval(StillPanMotion.settleDuration / 4)
        let current = settling.amount(at: resumeAt)
        let resumed = settling.moving(at: resumeAt)
        #expect(near(resumed.amount(at: resumeAt), current))
    }
}
