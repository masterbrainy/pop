import Foundation
import Testing
@testable import PopKit

/// Covers `SessionMachine`, the pure reducer behind `SessionController`'s Orbis
/// session lifecycle: warm-up, animating a page, reconnect backoff, falling back
/// after too many failed attempts, kill, and the credit meter (ROADMAP §2 Phase 3).
struct SessionMachineTests {
    private let machine = SessionMachine()
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func warmUpMintsThenConnectsThenBecomesReady() {
        var (state, effect) = machine.reduce(.initial, .warmUpRequested, now: t0)
        #expect(state.phase == .minting)
        #expect(effect == .mintToken)

        (state, effect) = machine.reduce(state, .tokenMinted(jwt: "jwt-1", expiresAt: t0.addingTimeInterval(3600)), now: t0)
        #expect(state.phase == .connecting)
        #expect(state.jwt == "jwt-1")
        #expect(effect == .connect(jwt: "jwt-1"))

        (state, effect) = machine.reduce(state, .connected(sessionId: "s-1"), now: t0)
        #expect(state.phase == .ready)
        #expect(state.sessionId == "s-1")
        #expect(state.connectedSince == t0)
        #expect(effect == nil)
    }

    @Test func aFailedInitialMintOrConnectGoesStraightToFailedWithNoRetryLadder() {
        var (state, effect) = machine.reduce(.initial, .tokenMintFailed("no network"), now: t0)
        #expect(state.phase == .idle)
        #expect(effect == nil) // tokenMintFailed only applies from .minting

        (state, _) = machine.reduce(.initial, .warmUpRequested, now: t0)
        (state, effect) = machine.reduce(state, .tokenMintFailed("no network"), now: t0)
        #expect(state.phase == .failed("no network"))
        #expect(effect == nil)

        var (connecting, _) = machine.reduce(.initial, .warmUpRequested, now: t0)
        (connecting, _) = machine.reduce(connecting, .tokenMinted(jwt: "jwt", expiresAt: t0.addingTimeInterval(60)), now: t0)
        let (failed, failEffect) = machine.reduce(connecting, .connectFailed("ICE failed"), now: t0)
        #expect(failed.phase == .failed("ICE failed"))
        #expect(failEffect == nil)
    }

    private func readyState(page: Int? = nil) -> SessionState {
        var (state, _) = machine.reduce(.initial, .warmUpRequested, now: t0)
        (state, _) = machine.reduce(state, .tokenMinted(jwt: "jwt-1", expiresAt: t0.addingTimeInterval(3600)), now: t0)
        (state, _) = machine.reduce(state, .connected(sessionId: "s-1"), now: t0)
        guard let page else { return state }
        (state, _) = machine.reduce(state, .animateRequested(page: page), now: t0)
        return state
    }

    @Test func animateRequestedMovesToAnimatingAndAsksTheDriverToShowThePage() {
        let ready = readyState()
        let (animating, effect) = machine.reduce(ready, .animateRequested(page: 2), now: t0)
        #expect(animating.phase == .animating(page: 2))
        #expect(animating.currentPage == 2)
        #expect(effect == .showPage(index: 2))
    }

    @Test func aDropWhileReadyOrAnimatingStartsTheReconnectLadderAtOneSecond() {
        for base in [readyState(), readyState(page: 3)] {
            let (reconnecting, effect) = machine.reduce(base, .disconnected("ICE disconnected"), now: t0)
            #expect(reconnecting.phase == .reconnecting(attempt: 1, backoff: 1))
            #expect(effect == .scheduleReconnect(after: 1))
            #expect(reconnecting.connectedSince == base.connectedSince) // credit meter keeps running
        }
    }

    /// A page that fails to prepare or start is not a dropped connection: the session stays
    /// connected and ready for the next page instead of starting a reconnect ladder whose
    /// `connect` the still-open session refuses (ending in fallback for the whole book).
    @Test func aStageFailureWhileConnectedGoesBackToReadyWithoutReconnecting() {
        for base in [readyState(), readyState(page: 3)] {
            let (state, effect) = machine.reduce(base, .stageFailed("conditions_ready did not arrive"), now: t0)
            #expect(state.phase == .ready)
            #expect(effect == nil)
            #expect(state.sessionId == base.sessionId)
            #expect(state.connectedSince == base.connectedSince)
            #expect(state.currentPage == nil)
            let (again, showEffect) = machine.reduce(state, .animateRequested(page: 4), now: t0)
            #expect(again.phase == .animating(page: 4))
            #expect(showEffect == .showPage(index: 4))
        }
    }

    @Test func backoffDoublesEachFailedAttemptUpToFiveThenFallsBack() {
        var state = readyState()
        (state, _) = machine.reduce(state, .disconnected("drop"), now: t0)
        #expect(state.phase == .reconnecting(attempt: 1, backoff: 1))

        let expectedBackoffs: [TimeInterval] = [2, 4, 8, 16]
        for expected in expectedBackoffs {
            let (next, effect) = machine.reduce(state, .connectFailed("still down"), now: t0)
            guard case let .reconnecting(_, backoff) = next.phase else {
                Issue.record("expected still reconnecting, got \(next.phase)")
                return
            }
            #expect(backoff == expected)
            #expect(effect == .scheduleReconnect(after: expected))
            state = next
        }

        // the 5th attempt has now failed too: give up and fall back to the still.
        let (fallenBack, effect) = machine.reduce(state, .connectFailed("still down"), now: t0)
        #expect(fallenBack.phase == .fallback)
        #expect(fallenBack.connectedSince == nil)
        #expect(effect == .disconnect)
    }

    @Test func reconnectTickReusesAValidJwtButMintsAFreshOneWhenItHasExpired() {
        var state = readyState()
        (state, _) = machine.reduce(state, .disconnected("drop"), now: t0)

        let (stillValid, effectWithValidJwt) = machine.reduce(state, .reconnectTick(now: t0.addingTimeInterval(1)), now: t0.addingTimeInterval(1))
        #expect(effectWithValidJwt == .connect(jwt: "jwt-1"))
        #expect(stillValid.phase == state.phase)

        let farFuture = t0.addingTimeInterval(10_000)
        let (expired, effectWithExpiredJwt) = machine.reduce(state, .reconnectTick(now: farFuture), now: farFuture)
        #expect(effectWithExpiredJwt == .mintToken)
        #expect(expired.phase == state.phase)
    }

    @Test func reconnectingAfterMintingAFreshTokenTriesToConnectWithIt() {
        var state = readyState()
        (state, _) = machine.reduce(state, .disconnected("drop"), now: t0)

        let (updated, effect) = machine.reduce(state, .tokenMinted(jwt: "jwt-2", expiresAt: t0.addingTimeInterval(3600)), now: t0)
        #expect(updated.jwt == "jwt-2")
        #expect(effect == .connect(jwt: "jwt-2"))
        #expect(updated.phase == state.phase) // still the same reconnect attempt, not yet resolved
    }

    @Test func reconnectingSuccessfullyResumesAnimatingTheSamePageOrGoesBackToReady() {
        var animating = readyState(page: 4)
        (animating, _) = machine.reduce(animating, .disconnected("drop"), now: t0)
        let (resumed, effect) = machine.reduce(animating, .connected(sessionId: "s-2"), now: t0)
        #expect(resumed.phase == .animating(page: 4))
        #expect(effect == .showPage(index: 4))

        var ready = readyState()
        (ready, _) = machine.reduce(ready, .disconnected("drop"), now: t0)
        let (backToReady, readyEffect) = machine.reduce(ready, .connected(sessionId: "s-3"), now: t0)
        #expect(backToReady.phase == .ready)
        #expect(readyEffect == nil)
    }

    @Test func killDisconnectsFromAConnectedPhaseAndDoesNothingIfAlreadyIdle() {
        let ready = readyState()
        let (killed, effect) = machine.reduce(ready, .killRequested, now: t0)
        #expect(killed.phase == .killed)
        #expect(killed.connectedSince == nil)
        #expect(effect == .disconnect)

        let (stillKilled, noEffect) = machine.reduce(killed, .killRequested, now: t0)
        #expect(stillKilled.phase == .killed)
        #expect(noEffect == nil)

        let (idleKilled, idleEffect) = machine.reduce(.initial, .killRequested, now: t0)
        #expect(idleKilled.phase == .killed)
        #expect(idleEffect == nil) // never connected, nothing to disconnect
    }

    @Test func creditMeterAccumulatesAtTheStableRateOnlyWhileConnected() {
        #expect(CreditMeter.credits(for: .initial, at: t0) == 0)

        let ready = readyState()
        let fiveMinutesLater = t0.addingTimeInterval(5 * 60)
        let credits = CreditMeter.credits(for: ready, at: fiveMinutesLater)
        #expect(abs(credits - 5 * 0.582) < 0.0001)

        let (killed, _) = machine.reduce(ready, .killRequested, now: t0)
        #expect(CreditMeter.credits(for: killed, at: fiveMinutesLater) == 0)
    }
}
