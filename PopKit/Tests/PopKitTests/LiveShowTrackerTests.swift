import Testing
@testable import PopKit

/// Covers `LiveShowTracker`: each page flow gets a generation, only the newest flow's
/// first frame marks the page live, and a flow that never shows a frame (or fails) is
/// retried once before the page settles on its still.
struct LiveShowTrackerTests {
    @Test func eachShowGetsANewerGeneration() {
        var tracker = LiveShowTracker()
        let first = tracker.begin(key: "a#1")
        let second = tracker.begin(key: "b#1")
        #expect(second > first)
        #expect(tracker.isCurrent(second))
        #expect(!tracker.isCurrent(first))
    }

    @Test func onlyTheNewestGenerationsFirstFrameCounts() {
        var tracker = LiveShowTracker()
        let old = tracker.begin(key: "a#1")
        let new = tracker.begin(key: "a#2")
        do { let result = tracker.firstFrame(generation: old); #expect(!result) }
        do { let result = tracker.firstFrame(generation: nil); #expect(!result) }
        do { let result = tracker.firstFrame(generation: new); #expect(result) }
        do { let result = tracker.firstFrame(generation: new); #expect(!result) } // once
    }

    @Test func leavingThePageDropsItsLateFirstFrame() {
        var tracker = LiveShowTracker()
        let generation = tracker.begin(key: "a#1")
        tracker.leave()
        #expect(!tracker.isCurrent(generation))
        do { let result = tracker.firstFrame(generation: generation); #expect(!result) }
    }

    @Test func aStalledFlowIsRetriedOnceWithANewGenerationThenGivesUp() {
        var tracker = LiveShowTracker()
        let generation = tracker.begin(key: "a#1")
        guard case let .retry(retry) = tracker.stalled(generation: generation) else {
            Issue.record("expected a retry")
            return
        }
        #expect(retry > generation)
        #expect(tracker.isCurrent(retry))
        do { let result = tracker.stalled(generation: retry); #expect(result == .giveUp) }
    }

    @Test func aStallOfAnOlderOrLiveGenerationIsIgnored() {
        var tracker = LiveShowTracker()
        let old = tracker.begin(key: "a#1")
        let live = tracker.begin(key: "b#1")
        do { let result = tracker.stalled(generation: old); #expect(result == .ignore) }
        do { let result = tracker.firstFrame(generation: live); #expect(result) }
        do { let result = tracker.stalled(generation: live); #expect(result == .ignore) }
    }

    @Test func aFirstFrameResetsTheRetryBudgetForThePage() {
        var tracker = LiveShowTracker()
        let generation = tracker.begin(key: "a#1")
        guard case let .retry(retry) = tracker.stalled(generation: generation) else {
            Issue.record("expected a retry")
            return
        }
        do { let result = tracker.firstFrame(generation: retry); #expect(result) }
        let again = tracker.begin(key: "a#1")
        if case .retry = tracker.stalled(generation: again) {} else { Issue.record("expected a fresh retry") }
    }

    @Test func aDifferentPageStartsWithAFreshRetryBudget() {
        var tracker = LiveShowTracker()
        let a = tracker.begin(key: "a#1")
        _ = tracker.stalled(generation: a)
        let b = tracker.begin(key: "b#1")
        if case .retry = tracker.stalled(generation: b) {} else { Issue.record("expected a retry for the new page") }
    }
}
