import Testing
@testable import PopKit

/// Feeds hinge samples through the machine and collects every event, like the app does.
private struct Run {
    let machine = PostureMachine()
    private(set) var state = PostureState.initial
    private(set) var events: [PostureEvent] = []

    mutating func feed(_ angle: Double, at time: Double = 0, posture: HingePosture? = nil) {
        let sample = HingeSample(posture: posture ?? Self.posture(for: angle), angle: angle, time: time)
        let (next, emitted) = machine.reduce(state, sample)
        state = next
        events += emitted
    }

    mutating func feed(_ angles: [Double]) {
        for angle in angles { feed(angle) }
    }

    mutating func clearEvents() { events = [] }

    private static func posture(for angle: Double) -> HingePosture {
        angle <= 0 ? .closed : angle >= 180 ? .fullyOpen : .partiallyOpen
    }
}

private func approx(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

struct PostureMachineTests {
    @Test func standardConfigIsOrderedAndValid() {
        #expect(PostureConfig.standard.isValid)
        let crossed = PostureConfig(openAngle: 120, turnAngle: 140, popStartAngle: 130, popFullAngle: 90, closedAngle: 10, closeHold: 1)
        #expect(!crossed.isValid)
    }

    @Test func startingFlatSettlesThePageSoItsAnimationCanStart() {
        var run = Run()
        run.feed(180)
        #expect(run.state.phase == .open(armed: true))
        #expect(run.events == [.pageSettled])
        #expect(run.state.curl == 0 && run.state.popDepth == 0)
    }

    @Test func startingClosedShowsTheCoverWithoutEvents() {
        var run = Run()
        run.feed(0)
        #expect(run.state.phase == .closed)
        #expect(run.events.isEmpty)
    }

    @Test func foldingFromFlatLiftsThePageInProportion() {
        var run = Run()
        // The curl runs from 167° (flat minus the 3° deadband) down to the 140° turn.
        run.feed([180, 175, 160])
        #expect(approx(run.state.curl, 7.0 / 27.0))
        run.feed(145)
        #expect(approx(run.state.curl, 22.0 / 27.0))
        #expect(run.events == [.pageSettled])
    }

    @Test func foldingPastTheTurnPointTurnsExactlyOnce() {
        var run = Run()
        run.feed([180, 150])
        run.clearEvents()
        run.feed([139, 142, 138, 141, 139.5, 150, 155])
        #expect(run.events == [.turnCommitted])
        #expect(run.state.curl == 0)
        #expect(run.state.phase == .open(armed: false))
    }

    @Test func openingBackBeforeTheTurnPointSettlesWithoutTurning() {
        var run = Run()
        run.feed([180, 150])
        run.clearEvents()
        run.feed(175)
        #expect(run.events == [.turnCancelled])
        #expect(run.state.phase == .open(armed: true))
        #expect(run.state.curl == 0)
    }

    @Test func reopeningAfterATurnSettlesTheNewPageAndAllowsTheNextTurn() {
        var run = Run()
        run.feed([180, 139])
        run.clearEvents()
        run.feed([165, 172])
        #expect(run.events == [.pageSettled])
        run.feed(139)
        #expect(run.events == [.pageSettled, .turnCommitted])
    }

    @Test func keepFoldingToNinetyPopsThePageNowShowingThenFlatFoldsItBack() {
        var run = Run()
        run.feed([180, 139])
        run.clearEvents()
        run.feed(110)
        #expect(run.events == [.popBegan])
        #expect(approx(run.state.popDepth, 0.5))
        run.feed(90)
        #expect(run.state.popDepth == 1)
        run.feed(60)
        #expect(run.state.popDepth == 1)
        run.feed([135, 180])
        #expect(run.events == [.popBegan, .popEnded, .pageSettled])
        #expect(run.state.popDepth == 0)
    }

    @Test func oneBigJumpFromFlatTurnsThenPops() {
        var run = Run()
        run.feed(180)
        run.clearEvents()
        run.feed(100)
        #expect(run.events == [.turnCommitted, .popBegan])
    }

    @Test func closingCountsOnlyAfterTheHold() {
        var run = Run()
        run.feed(180, at: 0)
        run.feed(60, at: 0.2)
        run.clearEvents()
        run.feed(0, at: 0.5)
        #expect(run.events == [.popEnded])
        #expect(run.state.needsTick)
        run.feed(0, at: 1.3)
        #expect(run.events == [.popEnded])
        run.feed(0, at: 1.5)
        #expect(run.events == [.popEnded, .closed])
        #expect(run.state.phase == .closed)
        #expect(!run.state.needsTick)
    }

    @Test func reopeningBeforeTheHoldJustCarriesOn() {
        var run = Run()
        run.feed(180, at: 0)
        run.feed(5, at: 1)
        run.clearEvents()
        run.feed(150, at: 1.6)
        #expect(!run.events.contains(.closed))
        #expect(run.state.phase == .open(armed: false))
        run.feed(175, at: 2)
        #expect(run.events == [.pageSettled])
    }

    @Test func theOsClosedStatusCountsAsClosedAtAnyAngle() {
        var run = Run()
        run.feed(180, at: 0)
        run.feed(12, at: 1, posture: .closed)
        run.feed(12, at: 2.1, posture: .closed)
        #expect(run.state.phase == .closed)
        #expect(run.events.last == .closed)
    }

    @Test func openingFromTheCoverPopsPageOneThenSettlesIt() {
        var run = Run()
        run.feed(0, at: 0)
        run.feed(30, at: 1)
        #expect(run.events == [.opened, .popBegan])
        #expect(run.state.popDepth == 1)
        run.feed(110, at: 1.5)
        #expect(approx(run.state.popDepth, 0.5))
        run.feed(178, at: 2)
        #expect(run.events == [.opened, .popBegan, .popEnded, .pageSettled])
    }

    @Test func openingFromTheCoverNeverTurnsAPage() {
        var run = Run()
        run.feed([0, 45, 120, 139, 150, 180])
        #expect(!run.events.contains(.turnCommitted))
    }

    @Test func anglesOutsideTheRangeAreClamped() {
        var run = Run()
        run.feed(200)
        #expect(run.state.angle == 180)
        run.feed(-5)
        #expect(run.state.angle == 0)
    }
}

/// R-26: a hinge resting near a threshold must not flap.
struct PostureHysteresisTests {
    @Test func aHingeRestingNearThePopAngleDoesNotFlapBetweenPopBeganAndPopEnded() {
        var run = Run()
        run.feed([180, 139, 131, 129.5, 130.5, 129.5, 130.5, 129.5])
        #expect(run.events.filter { $0 == .popBegan }.count == 1)
        #expect(!run.events.contains(.popEnded))
    }

    @Test func thePopUpStillEndsWhenTheBookOpensClearlyPastThePopAngle() {
        var run = Run()
        run.feed([180, 139, 120, 136])
        #expect(run.events.suffix(1) == [.popEnded])
        #expect(run.state.popDepth == 0)
    }

    @Test func jitterAtTheTopOfTheFoldCancelsTheCurlAtMostOnce() {
        var run = Run()
        run.feed([180, 165, 171, 169, 171, 169, 171])
        #expect(run.events.filter { $0 == .turnCancelled }.count == 1)
    }

    @Test func aTinyWobbleBelowFlatNeitherCurlsNorCancels() {
        var run = Run()
        run.feed([180, 169, 171, 168.5, 172])
        #expect(!run.events.contains(.turnCancelled))
        #expect(run.state.curl == 0)
    }
}
