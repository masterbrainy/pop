import Testing
@testable import PopKit

/// The demo's gesture model (`PostureConfig.closeToTurn`): folding the Duo to 80° or below and
/// opening it again turns the page. Folding less lifts nothing and turns nothing; the pop-up
/// at about 90° still works.
private struct Run {
    let machine = PostureMachine(config: .closeToTurn)
    private(set) var state = PostureState.initial
    private(set) var events: [PostureEvent] = []
    private(set) var maxCurl = 0.0

    mutating func feed(_ angle: Double, at time: Double = 0) {
        let posture: HingePosture = angle <= 0 ? .closed : angle >= 180 ? .fullyOpen : .partiallyOpen
        let (next, emitted) = machine.reduce(state, HingeSample(posture: posture, angle: angle, time: time))
        state = next
        events += emitted
        maxCurl = max(maxCurl, next.curl)
    }

    mutating func feed(_ angles: [Double]) {
        for angle in angles { feed(angle) }
    }

    func count(_ event: PostureEvent) -> Int { events.filter { $0 == event }.count }
}

struct CloseToTurnPostureTests {
    @Test func theDemoConfigIsValidAndUsesCloseToTurn() {
        #expect(PostureConfig.closeToTurn.isValid)
        #expect(PostureConfig.closeToTurn.gesture == .closeAndReopen)
        #expect(PostureConfig.standard.gesture == .fold)
    }

    @Test func foldingPastTheOldTurnPointNeitherTurnsNorCurls() {
        var run = Run()
        run.feed([180, 160, 140, 120, 140, 160, 180])
        #expect(run.count(.turnCommitted) == 0)
        #expect(run.count(.turnCancelled) == 0)
        #expect(run.maxCurl == 0)
    }

    @Test func aQuickCloseAndReopenTurnsThePageOnceAndSettlesIt() {
        var run = Run()
        run.feed(180, at: 0)
        run.feed(0, at: 0.2)
        run.feed(180, at: 0.5)
        #expect(run.count(.turnCommitted) == 1)
        #expect(run.events.last == .pageSettled)
    }

    @Test func aLongCloseThenReopenTurnsOnceAndNeverJumpsBackToPageOne() {
        var run = Run()
        run.feed(180, at: 0)
        run.feed(0, at: 1)
        run.feed(0, at: 5)
        #expect(run.state.phase == .closed)
        run.feed(180, at: 9)
        #expect(run.count(.turnCommitted) == 1)
        #expect(run.count(.opened) == 0)
    }

    @Test func theSimulatorsSparseEndPointsStillTurn() {
        var run = Run()
        run.feed(167, at: 0)
        run.feed(0, at: 1)
        run.feed(180, at: 2)
        #expect(run.count(.turnCommitted) == 1)
    }

    @Test func closingFromAPopUpTurnsOnReopen() {
        var run = Run()
        run.feed([180, 130, 110, 90])
        #expect(run.count(.popBegan) == 1)
        run.feed(0, at: 1)
        run.feed(180, at: 2)
        #expect(run.count(.popEnded) == 1)
        #expect(run.count(.turnCommitted) == 1)
    }

    @Test func thePopUpStillRisesAndFoldsBackWithoutTurning() {
        var run = Run()
        run.feed([180, 130, 110, 90])
        #expect(run.state.popDepth == 1)
        run.feed([120, 150, 180])
        #expect(run.count(.popBegan) == 1)
        #expect(run.count(.popEnded) == 1)
        #expect(run.count(.turnCommitted) == 0)
    }

    @Test func openingFromTheCoverAtTheStartOpensWithoutTurning() {
        var run = Run()
        run.feed(0, at: 0)
        run.feed(180, at: 1)
        #expect(run.count(.opened) == 1)
        #expect(run.count(.turnCommitted) == 0)
    }

    @Test func reopeningPartWaySettlesOnlyOnceTheBookIsFlat() {
        var run = Run()
        run.feed(180, at: 0)
        run.feed(0, at: 1)
        run.feed(150, at: 2)
        #expect(run.count(.turnCommitted) == 1)
        #expect(run.count(.pageSettled) == 1)
        run.feed(180, at: 3)
        #expect(run.count(.pageSettled) == 2)
    }

    @Test func foldingJustPastEightyAndBackTurnsThePage() {
        var run = Run()
        run.feed([180, 120, 90, 75])
        run.feed([110, 150, 180])
        #expect(run.count(.turnCommitted) == 1)
    }

    @Test func foldingToNinetyForThePopUpAndBackDoesNotTurn() {
        var run = Run()
        run.feed([180, 120, 90, 85, 120, 180])
        #expect(run.count(.turnCommitted) == 0)
    }

    @Test func aHingeWobblingAroundEightyTurnsOnlyOnceItClearlyReopens() {
        var run = Run()
        run.feed([180, 79, 81, 79, 85, 95, 79])
        #expect(run.count(.turnCommitted) == 0)
        run.feed(180)
        #expect(run.count(.turnCommitted) == 1)
    }

    @Test func twoCloseAndReopenCyclesTurnTwoPages() {
        var run = Run()
        run.feed(180, at: 0)
        run.feed(0, at: 1)
        run.feed(180, at: 2)
        run.feed(0, at: 3)
        run.feed(0, at: 6)
        run.feed(180, at: 7)
        #expect(run.count(.turnCommitted) == 2)
    }
}
