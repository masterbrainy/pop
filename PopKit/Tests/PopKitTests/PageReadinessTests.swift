import Foundation
import Testing
@testable import PopKit

/// "No page until painted": when a page is good to show (words and picture), and when page 1
/// waits for the parent's opening prompt.
struct PageReadinessTests {
    private let stored = Date(timeIntervalSince1970: 1_000)
    private let words = PageContent(index: 1, text: "The kite pulls her up.", artPrompt: "a kite")
    private var painted: PageContent { words.with(stillPath: "/tmp/p1.png") }

    private func readiness(
        _ page: PageContent?, picture: PictureState = .painting, motion: MotionState = .pending,
        storedAt: Date? = nil, secondsLater: TimeInterval = 0, requiresMotion: Bool = false
    ) -> PageReadiness {
        PageReadiness.of(page: page, picture: picture, motion: motion, stillStoredAt: storedAt,
                         now: (storedAt ?? stored).addingTimeInterval(secondsLater), requiresMotion: requiresMotion)
    }

    @Test func aPageWithoutWordsIsStillBeingWritten() {
        #expect(readiness(nil) == .writing)
        #expect(readiness(PageContent(index: 0, text: "")) == .writing)
        #expect(!readiness(PageContent(index: 0, text: "")).isReady)
    }

    @Test func wordsWithoutAPictureArePaintingNotReady() {
        let state = readiness(words)
        #expect(state == .painting)
        #expect(!state.isReady)
    }

    @Test func thePageOnScreenIsReadyOnceItsStillIsStoredWithoutWaitingForMotion() {
        #expect(readiness(painted, picture: .stored, storedAt: stored) == .ready(picture: true))
    }

    @Test func thePageBehindWaitsForItsMotionPromptOrTheGraceAfterTheStill() {
        #expect(readiness(painted, picture: .stored, storedAt: stored, secondsLater: 3, requiresMotion: true) == .painting)
        #expect(readiness(painted, picture: .stored, storedAt: stored, secondsLater: PaintDeadlines.motionGrace, requiresMotion: true)
            == .ready(picture: true))
        #expect(readiness(painted, picture: .stored, motion: .ready, storedAt: stored, secondsLater: 1, requiresMotion: true)
            == .ready(picture: true))
        #expect(readiness(painted, picture: .stored, motion: .failed, storedAt: stored, secondsLater: 1, requiresMotion: true)
            == .ready(picture: true))
    }

    @Test func aStillWithNoRecordedStoreTimeDoesNotWaitForMotion() {
        #expect(readiness(painted, picture: .stored, storedAt: nil, requiresMotion: true) == .ready(picture: true))
    }

    @Test func anUnavailableOrGivenUpPictureIsReadyWithoutAPicture() {
        #expect(readiness(words, picture: .unavailable) == .ready(picture: false))
        #expect(readiness(words, picture: .gaveUp, requiresMotion: true) == .ready(picture: false))
    }

    @Test func aStillThatLandsAfterGivingUpStillShows() {
        #expect(readiness(painted, picture: .gaveUp, storedAt: stored) == .ready(picture: true))
    }

    @Test func theDeadlinesLeaveRoomForAPictureAndItsRetry() {
        // Page 1 fits a picture redone after a moderation flag, or a quick failure and its retry.
        #expect(PaintDeadlines.firstPage >= PaintDeadlines.redonePicture + PaintDeadlines.artRetryDelay)
        #expect(PaintDeadlines.firstPage >= 2 * PaintDeadlines.typicalPicture + PaintDeadlines.artRetryDelay)
        // The page behind (the parent is still reading) fits a redone picture and its retry.
        #expect(PaintDeadlines.pageBehind >= PaintDeadlines.redonePicture + PaintDeadlines.artRetryDelay + PaintDeadlines.typicalPicture)
        #expect(PaintDeadlines.waitForPageBehind > PaintDeadlines.pageBehind)
        // The retry waits less than a whole call may take, so it never outlasts the app's art timeout by much.
        #expect(PaintDeadlines.artRetryDelay < PopServerTimeouts.art)
    }
}

/// "No page until prompted": what the empty book says before and while page 1 is made.
struct OpeningStateTests {
    private let empty = PageContent(index: 0, text: "")
    private let written = PageContent(index: 0, text: "Once upon a time, a fox found a leaf.")

    @Test func anEmptyPageWithNoPromptAwaitsThePromptAndIsNeverWriting() {
        #expect(OpeningState.of(current: empty, isWritingFirst: false, heroPending: false, readiness: .writing) == .awaitingPrompt)
        #expect(OpeningState.of(current: empty, isWritingFirst: false, heroPending: true, readiness: .writing) == .awaitingPrompt)
        #expect(OpeningState.of(current: nil, isWritingFirst: false, heroPending: false, readiness: .writing) == .awaitingPrompt)
    }

    @Test func aPromptWaitsForTheHeroThenWrites() {
        #expect(OpeningState.of(current: empty, isWritingFirst: true, heroPending: true, readiness: .writing) == .preparingHero)
        #expect(OpeningState.of(current: empty, isWritingFirst: true, heroPending: false, readiness: .writing) == .writing)
    }

    @Test func wordsWaitForTheirPictureThenShow() {
        #expect(OpeningState.of(current: written, isWritingFirst: true, heroPending: false, readiness: .painting) == .painting)
        #expect(OpeningState.of(current: written, isWritingFirst: false, heroPending: false, readiness: .ready(picture: true)) == .shown)
        #expect(OpeningState.of(current: written, isWritingFirst: true, heroPending: false, readiness: .ready(picture: false)) == .shown)
    }

    @Test func theLeftPageInvitesThePromptThenQuotesItWhileThePageIsMade() {
        #expect(OpeningState.awaitingPrompt.leftPage(prompt: nil, isSlow: false) == "How does the story begin? Say it or type it below.")
        #expect(OpeningState.preparingHero.leftPage(prompt: "a fox", isSlow: false) == "Getting your hero ready…\n\n“a fox”")
        #expect(OpeningState.writing.leftPage(prompt: "a fox", isSlow: false) == "Making your first page…\n\n“a fox”")
        #expect(OpeningState.painting.leftPage(prompt: "a fox", isSlow: true) == "Making your first page…\n\n“a fox”\n\nAlmost there…")
        #expect(OpeningState.shown.leftPage(prompt: "a fox", isSlow: false) == nil)
    }
}
