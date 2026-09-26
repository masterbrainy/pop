import Foundation
import Testing
@testable import PopKit

/// Covers `PreRollPlanner`: one Orbis session animates the page on screen until its loop is
/// ready, then hands over to the loop and pre-animates the page behind, hidden, so a fold
/// shows either its live video (revealed) or its finished loop.
struct PreRollPlannerTests {
    private typealias Planner = PreRollPlanner
    private typealias Page = PreRollPlanner.Page
    private typealias Slot = PreRollPlanner.Slot

    private static let one = PageKey(id: UUID(), version: 1)
    private static let two = PageKey(id: UUID(), version: 1)
    private static let twoRewritten = PageKey(id: UUID(), version: 2)
    private static let three = PageKey(id: UUID(), version: 1)

    private static func page(_ key: PageKey, ready: Bool = true, clip: Bool = false, held: Bool = false, spent: Bool = false) -> Page {
        Page(key: key, canAnimate: ready, hasClip: clip, isHeld: held, isSpent: spent)
    }

    private static func slot(_ key: PageKey, hidden: Bool = false, firstFrame: Bool = false) -> Slot {
        Slot(key: key, isHidden: hidden, hasFirstFrame: firstFrame)
    }

    // MARK: - the page on screen

    @Test func aReadyPageOnScreenAnimatesInView() {
        let plan = Planner.plan(onScreen: Self.page(Self.one), behind: Self.page(Self.two), slot: nil)
        #expect(plan.actions == [.animate(Self.one, hidden: false)])
        #expect(plan.display == .still)
    }

    @Test func thePageOnScreenGoesLiveOnItsFirstFrame() {
        let plan = Planner.plan(onScreen: Self.page(Self.one), behind: Self.page(Self.two), slot: Self.slot(Self.one, firstFrame: true))
        #expect(plan.actions.isEmpty)
        #expect(plan.display == .live)
    }

    @Test func aPageOnScreenWithoutStillOrPromptWaitsAndThePageBehindWaitsToo() {
        let plan = Planner.plan(onScreen: Self.page(Self.one, ready: false), behind: Self.page(Self.two), slot: nil)
        #expect(plan.actions.isEmpty)
        #expect(plan.display == .still)
        #expect(plan.target == nil)
    }

    @Test func noPageMeansNothingToDo() {
        let plan = Planner.plan(onScreen: nil, behind: nil, slot: nil)
        #expect(plan.actions.isEmpty)
        #expect(plan.display == .still)
    }

    // MARK: - hand-over to the loop, then the page behind

    @Test func whileThePageOnScreenHasNoLoopThePageBehindWaits() {
        let plan = Planner.plan(onScreen: Self.page(Self.one), behind: Self.page(Self.two), slot: Self.slot(Self.one, firstFrame: true))
        #expect(plan.target == .init(key: Self.one, hidden: false))
    }

    @Test func onceTheLoopIsReadyThePageHandsOverAndTheSessionPreAnimatesThePageBehind() {
        let plan = Planner.plan(onScreen: Self.page(Self.one, clip: true), behind: Self.page(Self.two), slot: Self.slot(Self.one, firstFrame: true))
        #expect(plan.display == .clip)
        #expect(plan.actions == [.animate(Self.two, hidden: true)])
    }

    @Test func thePageBehindIsPreAnimatedOnlyOnceItHasAStillAndAMotionPrompt() {
        let waiting = Planner.plan(onScreen: Self.page(Self.one, clip: true), behind: Self.page(Self.two, ready: false), slot: Self.slot(Self.one, firstFrame: true))
        #expect(waiting.actions == [.idle])
        let ready = Planner.plan(onScreen: Self.page(Self.one, clip: true), behind: Self.page(Self.two), slot: nil)
        #expect(ready.actions == [.animate(Self.two, hidden: true)])
    }

    @Test func aPreAnimationInProgressIsLeftAlone() {
        let plan = Planner.plan(onScreen: Self.page(Self.one, clip: true), behind: Self.page(Self.two), slot: Self.slot(Self.two, hidden: true, firstFrame: true))
        #expect(plan.actions.isEmpty)
        #expect(plan.display == .clip)
    }

    @Test func aRewrittenPageBehindAbortsTheOldPreAnimationAndStartsTheNewOne() {
        let plan = Planner.plan(onScreen: Self.page(Self.one, clip: true), behind: Self.page(Self.twoRewritten), slot: Self.slot(Self.two, hidden: true, firstFrame: true))
        #expect(plan.actions == [.animate(Self.twoRewritten, hidden: true)])
    }

    @Test func aRewrittenPageBehindWithoutItsPictureYetStopsTheOldPreAnimation() {
        let plan = Planner.plan(onScreen: Self.page(Self.one, clip: true), behind: Self.page(Self.twoRewritten, ready: false), slot: Self.slot(Self.two, hidden: true))
        #expect(plan.actions == [.idle])
    }

    @Test func aPageBehindThatAlreadyHasItsLoopNeedsNoSession() {
        let plan = Planner.plan(onScreen: Self.page(Self.one, clip: true), behind: Self.page(Self.two, clip: true), slot: Self.slot(Self.two, hidden: true, firstFrame: true))
        #expect(plan.actions == [.idle])
        #expect(plan.target == nil)
    }

    @Test func theSessionIdlesAtTheEnding() {
        let plan = Planner.plan(onScreen: Self.page(Self.one, clip: true), behind: nil, slot: Self.slot(Self.one, firstFrame: true))
        #expect(plan.actions == [.idle])
        #expect(plan.display == .clip)
        let idle = Planner.plan(onScreen: Self.page(Self.one, clip: true), behind: nil, slot: nil)
        #expect(idle.actions.isEmpty)
    }

    // MARK: - the fold

    @Test func foldingToAPreAnimatedPageWithFramesRevealsIt() {
        let plan = Planner.plan(onScreen: Self.page(Self.two), behind: Self.page(Self.three), slot: Self.slot(Self.two, hidden: true, firstFrame: true))
        #expect(plan.actions == [.reveal(Self.two)])
        // Still until the reveal lands; then the same page shows live.
        #expect(plan.display == .still)
        let revealed = Planner.plan(onScreen: Self.page(Self.two), behind: Self.page(Self.three), slot: Self.slot(Self.two, firstFrame: true))
        #expect(revealed.actions.isEmpty)
        #expect(revealed.display == .live)
    }

    @Test func foldingToAPreAnimatedPageStillPreparingRevealsItAndItGoesLiveOnItsFirstFrame() {
        let plan = Planner.plan(onScreen: Self.page(Self.two), behind: Self.page(Self.three), slot: Self.slot(Self.two, hidden: true))
        #expect(plan.actions == [.reveal(Self.two)])
        let preparing = Planner.plan(onScreen: Self.page(Self.two), behind: Self.page(Self.three), slot: Self.slot(Self.two))
        #expect(preparing.display == .still)
        #expect(preparing.actions.isEmpty)
    }

    @Test func foldingToAPageWhoseLoopIsReadyPlaysItAndPreAnimatesTheNextOne() {
        let plan = Planner.plan(onScreen: Self.page(Self.two, clip: true), behind: Self.page(Self.three), slot: nil)
        #expect(plan.display == .clip)
        #expect(plan.actions == [.animate(Self.three, hidden: true)])
    }

    @Test func foldingToAPageThatWasNeverPreAnimatedAnimatesItInView() {
        let plan = Planner.plan(onScreen: Self.page(Self.two), behind: Self.page(Self.three), slot: Self.slot(Self.one, firstFrame: true))
        #expect(plan.actions == [.animate(Self.two, hidden: false)])
        #expect(plan.display == .still)
    }

    @Test func aLivePageNeverShowsOverAnotherPage() {
        let plan = Planner.plan(onScreen: Self.page(Self.one, ready: false), behind: nil, slot: Self.slot(Self.two, firstFrame: true))
        #expect(plan.display == .still)
    }

    // MARK: - turning back, held and spent pages

    @Test func turningBackToAPageWithALoopPlaysIt() {
        // Page two was live on screen; turning back makes it the page behind, and it keeps recording.
        let plan = Planner.plan(onScreen: Self.page(Self.one, clip: true), behind: Self.page(Self.two), slot: Self.slot(Self.two, firstFrame: true))
        #expect(plan.display == .clip)
        #expect(plan.actions.isEmpty)
    }

    @Test func aHeldPageIsNeverAnimated() {
        let heldOnScreen = Planner.plan(onScreen: Self.page(Self.one, held: true), behind: Self.page(Self.two), slot: Self.slot(Self.one, firstFrame: true))
        #expect(heldOnScreen.display == .still)
        #expect(heldOnScreen.actions == [.animate(Self.two, hidden: true)])
        let heldBehind = Planner.plan(onScreen: Self.page(Self.one, clip: true), behind: Self.page(Self.two, held: true), slot: nil)
        #expect(heldBehind.actions.isEmpty)
        #expect(heldBehind.target == nil)
    }

    @Test func aSpentPageBehindIsNotPreAnimatedAgain() {
        let plan = Planner.plan(onScreen: Self.page(Self.one, clip: true), behind: Self.page(Self.two, spent: true), slot: nil)
        #expect(plan.actions.isEmpty)
    }

    @Test func aPageOnScreenThatGaveUpKeepsItsStillAndFreesTheSessionForThePageBehind() {
        let plan = Planner.plan(onScreen: Self.page(Self.one, spent: true), behind: Self.page(Self.two), slot: nil)
        #expect(plan.display == .still)
        #expect(plan.actions == [.animate(Self.two, hidden: true)])
    }
}
