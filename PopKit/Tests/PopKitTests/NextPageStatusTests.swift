import Foundation
import Testing
@testable import PopKit

/// What the "next page" banner and corner arrow show while a direction rebuilds the page behind.
struct NextPageStatusTests {
    private let onScreen = PageContent(index: 1, text: "The kite pulls her up.")
    private let behind = PageContent(index: 2, text: "She lands softly.")

    @Test func nothingFollowsTheEndingOrAPageStillBeingWritten() {
        #expect(NextPageStatus.of(current: onScreen, isEnding: true, pendingNext: nil, direction: nil, rewrittenPageId: nil) == .none)
        #expect(NextPageStatus.of(current: PageContent(index: 0, text: ""), isEnding: false, pendingNext: nil, direction: "snow", rewrittenPageId: nil) == .none)
        #expect(NextPageStatus.of(current: nil, isEnding: false, pendingNext: nil, direction: nil, rewrittenPageId: nil) == .none)
    }

    @Test func withoutWordsBehindThePageIsBeingWrittenAndCantTurn() {
        let status = NextPageStatus.of(current: onScreen, isEnding: false, pendingNext: nil, direction: nil, rewrittenPageId: nil)
        #expect(status == .writing)
        #expect(!status.canTurn)
    }

    @Test func aDirectionInFlightShowsItIsRewritingAndTheOldPageBehindStillTurns() {
        let status = NextPageStatus.of(current: onScreen, isEnding: false, pendingNext: behind, direction: "make it snow", rewrittenPageId: nil)
        #expect(status == .rewriting(direction: "make it snow", canTurn: true))
        #expect(status.canTurn)
    }

    @Test func aDirectionBeforeThereIsAnyPageBehindCantTurnYet() {
        let status = NextPageStatus.of(current: onScreen, isEnding: false, pendingNext: nil, direction: "make it snow", rewrittenPageId: nil)
        #expect(status == .rewriting(direction: "make it snow", canTurn: false))
        #expect(!status.canTurn)
    }

    @Test func aPageBehindWithWordsIsReadyAndSaysWhenADirectionRewroteIt() {
        let plain = NextPageStatus.of(current: onScreen, isEnding: false, pendingNext: behind, direction: nil, rewrittenPageId: nil)
        #expect(plain == .ready(rewritten: false))
        #expect(plain.canTurn)
        let rewritten = NextPageStatus.of(current: onScreen, isEnding: false, pendingNext: behind, direction: nil, rewrittenPageId: behind.id)
        #expect(rewritten == .ready(rewritten: true))
    }
}
