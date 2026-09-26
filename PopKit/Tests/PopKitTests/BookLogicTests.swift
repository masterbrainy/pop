import CoreGraphics
import Testing
@testable import PopKit

struct HingeScriptTests {
    @Test func sweepIncludesBothEndsInEvenSteps() {
        #expect(HingeScript.sweep(from: 180, to: 160, step: 5) == [180, 175, 170, 165, 160])
        #expect(HingeScript.sweep(from: 90, to: 100, step: 4) == [90, 94, 98, 100])
    }

    @Test func namedMovesReturnToFlat() {
        for move in [HingeScript.Move.turn, .pop] {
            let angles = HingeScript.angles(for: move)
            #expect(angles.first == 180)
            #expect(angles.last == 180)
        }
        #expect(HingeScript.angles(for: .close).last == 0)
        #expect(HingeScript.angles(for: .open).last == 180)
    }

    @Test func turnGoesPastTheTurnPointAndPopReachesNinety() {
        #expect(HingeScript.angles(for: .turn).min()! < PostureConfig.standard.turnAngle)
        #expect(HingeScript.angles(for: .turn).min()! <= PostureConfig.closeToTurn.turnAngle)
        #expect(HingeScript.angles(for: .pop).min()! <= PostureConfig.standard.popFullAngle)
    }

    @Test func parsesACommaSeparatedScriptAndSkipsUnknownMoves() {
        #expect(HingeScript.parse("turn, pop,close,wiggle") == [.turn, .pop, .close])
        #expect(HingeScript.parse("") == [])
    }

    @Test func aScriptedTurnDrivesTheMachineToExactlyOneTurn() {
        let machine = PostureMachine()
        let (_, events) = HingeScript.angles(for: .turn).enumerated().reduce((PostureState.initial, [PostureEvent]())) { acc, item in
            let (state, events) = machine.reduce(acc.0, HingeSample(posture: .partiallyOpen, angle: item.element, time: Double(item.offset) * 0.05))
            return (state, acc.1 + events)
        }
        #expect(events.filter { $0 == .turnCommitted }.count == 1)
        #expect(events.last == .pageSettled)
    }
}

struct BookNavigatorTests {
    @Test func readingTurnsForwardUntilTheLastPage() {
        let navigator = BookNavigator(pageCount: 3, mode: .reading)
        let (second, outcome) = navigator.turningForward()
        #expect(outcome == .turned(to: 1))
        let (third, _) = second.turningForward()
        let (stillThird, atEnd) = third.turningForward()
        #expect(atEnd == .atEnd)
        #expect(stillThird.index == 2)
    }

    @Test func creatingPastTheLastPageAddsANewPage() {
        let navigator = BookNavigator(pageCount: 2, mode: .creating, index: 1)
        let (next, outcome) = navigator.turningForward()
        #expect(outcome == .newPage(index: 2))
        #expect(next.index == 2 && next.pageCount == 3)
    }

    @Test func turningBackStopsAtTheFirstPage() {
        let navigator = BookNavigator(pageCount: 3, mode: .reading, index: 1)
        #expect(navigator.turningBack().index == 0)
        #expect(navigator.turningBack().turningBack().index == 0)
    }

    @Test func openingFromTheCoverShowsPageOne() {
        let navigator = BookNavigator(pageCount: 4, mode: .reading, index: 3)
        #expect(navigator.openedFromCover().index == 0)
    }

    @Test func anEmptyBookInCreationStartsWithOnePage() {
        #expect(BookNavigator(pageCount: 0, mode: .creating).pageCount == 1)
    }
}

struct SafeInsetsTests {
    private let pane = CGSize(width: 475, height: 669)

    @Test func noRegionsMeansNoExtraInsets() {
        #expect(SafeInsets.avoiding([], in: pane) == .zero)
    }

    @Test func aFoldStripOnTheLeadingEdgePadsTheLeadingSide() {
        let fold = CGRect(x: -12, y: 0, width: 30, height: 669)
        #expect(SafeInsets.avoiding([fold], in: pane) == SafeInsets(top: 0, leading: 18, bottom: 0, trailing: 0))
    }

    @Test func aFoldStripOnTheTrailingEdgePadsTheTrailingSide() {
        let fold = CGRect(x: 460, y: 0, width: 30, height: 669)
        #expect(SafeInsets.avoiding([fold], in: pane) == SafeInsets(top: 0, leading: 0, bottom: 0, trailing: 15))
    }

    @Test func aCameraAtTheTopPadsTheTop() {
        let camera = CGRect(x: 382, y: 0, width: 84, height: 170)
        #expect(SafeInsets.avoiding([camera], in: pane) == SafeInsets(top: 170, leading: 0, bottom: 0, trailing: 0))
    }

    @Test func regionsOutsideThePaneAreIgnored() {
        let elsewhere = CGRect(x: 600, y: 0, width: 40, height: 40)
        #expect(SafeInsets.avoiding([elsewhere], in: pane) == .zero)
    }

    @Test func overlappingRegionsTakeTheLargestInsetPerEdge() {
        let regions = [CGRect(x: 0, y: 0, width: 10, height: 669), CGRect(x: -5, y: 0, width: 25, height: 669)]
        #expect(SafeInsets.avoiding(regions, in: pane).leading == 20)
    }
}
