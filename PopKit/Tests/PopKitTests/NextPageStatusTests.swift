import Foundation
import Testing
@testable import PopKit

/// What the "next page" banner and corner arrow show about the page behind: a direction
/// rebuilding it, and a page that isn't turned to until its picture is finished.
struct NextPageStatusTests {
    private let onScreen = PageContent(index: 1, text: "The kite pulls her up.")
    private let behind = PageContent(index: 2, text: "She lands softly.")

    private func status(
        current: PageContent?, currentShown: Bool = true, isEnding: Bool = false, pendingNext: PageContent?,
        behindReady: Bool = true, direction: String? = nil, rewrittenPageId: UUID? = nil, lastDirection: String? = nil
    ) -> NextPageStatus {
        NextPageStatus.of(current: current, currentShown: currentShown, isEnding: isEnding, pendingNext: pendingNext,
                          behindReady: behindReady, direction: direction, rewrittenPageId: rewrittenPageId, lastDirection: lastDirection)
    }

    @Test func nothingFollowsTheEndingOrAPageStillBeingWritten() {
        #expect(status(current: onScreen, isEnding: true, pendingNext: nil) == .none)
        #expect(status(current: PageContent(index: 0, text: ""), pendingNext: nil, direction: "snow") == .none)
        #expect(status(current: nil, pendingNext: nil) == .none)
    }

    @Test func nothingFollowsAPageThatIsNotShownYet() {
        // Page 1 has its words but its picture is still being made: no arrow, no banner.
        #expect(status(current: onScreen, currentShown: false, pendingNext: behind) == .none)
        #expect(status(current: onScreen, currentShown: false, pendingNext: nil, direction: "snow") == .none)
    }

    @Test func withoutWordsBehindThePageIsBeingWrittenAndCantTurn() {
        let next = status(current: onScreen, pendingNext: nil)
        #expect(next == .writing)
        #expect(!next.canTurn)
    }

    @Test func wordsBehindWithoutTheirPictureArePaintingAndCantTurn() {
        let next = status(current: onScreen, pendingNext: behind, behindReady: false)
        #expect(next == .painting)
        #expect(!next.canTurn)
    }

    @Test func aDirectionInFlightShowsItIsRewritingAndTheOldPageBehindStillTurnsWhenPainted() {
        let next = status(current: onScreen, pendingNext: behind, direction: "make it snow")
        #expect(next == .rewriting(direction: "make it snow", canTurn: true))
        #expect(next.canTurn)
    }

    @Test func aDirectionWhileTheOldPageBehindIsStillPaintingCantTurn() {
        let next = status(current: onScreen, pendingNext: behind, behindReady: false, direction: "make it snow")
        #expect(next == .rewriting(direction: "make it snow", canTurn: false))
        #expect(!next.canTurn)
    }

    @Test func aDirectionBeforeThereIsAnyPageBehindCantTurnYet() {
        let next = status(current: onScreen, pendingNext: nil, direction: "make it snow")
        #expect(next == .rewriting(direction: "make it snow", canTurn: false))
        #expect(!next.canTurn)
    }

    @Test func theRewrittenPageKeepsSayingRewritingUntilItIsPainted() {
        let painting = status(current: onScreen, pendingNext: behind, behindReady: false, rewrittenPageId: behind.id, lastDirection: "make it snow")
        #expect(painting == .rewriting(direction: "make it snow", canTurn: false))
        let done = status(current: onScreen, pendingNext: behind, behindReady: true, rewrittenPageId: behind.id, lastDirection: "make it snow")
        #expect(done == .ready(rewritten: true))
    }

    @Test func aPageBehindWithWordsAndPictureIsReadyAndSaysWhenADirectionRewroteIt() {
        let plain = status(current: onScreen, pendingNext: behind)
        #expect(plain == .ready(rewritten: false))
        #expect(plain.canTurn)
        #expect(status(current: onScreen, pendingNext: behind, rewrittenPageId: behind.id) == .ready(rewritten: true))
    }
}
