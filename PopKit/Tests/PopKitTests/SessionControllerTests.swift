import Foundation
import Testing
@testable import PopKit

/// Covers `SessionController`, the driver around `SessionMachine`: it mints and
/// connects through a fake `PopServer` and `SceneTransport`, reconnects using a fake
/// clock (no real waiting), and eventually falls back after too many failed
/// attempts (ROADMAP §2 Phase 3).
struct SessionControllerTests {
    private let t0 = Date(timeIntervalSince1970: 2_000_000)

    private func readyServer(jwt: String = "jwt-1", expiresInSeconds: Double = 3600) async -> FakePopServer {
        let server = FakePopServer()
        let expiresAt = t0.addingTimeInterval(expiresInSeconds).timeIntervalSince1970
        await server.onReactorMint { ReactorMintResponse(jwt: jwt, expiresAt: expiresAt) }
        return server
    }

    /// Waits a little real time so a controller's background reconnect `Task` gets
    /// a chance to run; the fake clock itself never actually sleeps.
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(30))
    }

    @Test func warmUpMintsConnectsAndBecomesReady() async throws {
        let server = await readyServer()
        let transport = FakeSceneTransport()
        let controller = SessionController(server: server, transport: transport, clock: FakeSessionClock(now: t0))

        await controller.warmUp()

        let state = await controller.state
        #expect(state.phase == .ready)
        #expect(state.sessionId == "session-for-jwt-1")
        let connectCalls = await transport.connectCalls
        #expect(connectCalls == ["jwt-1"])
    }

    @Test func animateCallsPrepareThenStartWithTheGivenStillAndPrompt() async throws {
        let server = await readyServer()
        let transport = FakeSceneTransport()
        let controller = SessionController(server: server, transport: transport, clock: FakeSessionClock(now: t0))
        await controller.warmUp()

        let still = Data([1, 2, 3])
        let outcome = await controller.animate(page: 2, still: still, prompt: "a fox sways", generation: 1)

        #expect(outcome == .started)
        let state = await controller.state
        #expect(state.phase == .animating(page: 2))
        let prepareCalls = await transport.prepareCalls
        #expect(prepareCalls.count == 1 && prepareCalls[0].still == still && prepareCalls[0].prompt == "a fox sways")
        #expect(prepareCalls[0].generation == 1)
        #expect(await transport.startGenerations == [1])
    }

    @Test func aDropReconnectsAndResumesTheSamePageUsingTheFakeClockWithNoRealDelay() async throws {
        let server = await readyServer()
        let transport = FakeSceneTransport()
        let clock = FakeSessionClock(now: t0)
        let controller = SessionController(server: server, transport: transport, clock: clock)
        await controller.warmUp()
        _ = await controller.animate(page: 4, still: Data(), prompt: "prompt", generation: 1)

        await controller.reportDisconnected("ICE dropped")
        try await settle()

        let state = await controller.state
        #expect(state.phase == .animating(page: 4))
        let connectCalls = await transport.connectCalls
        #expect(connectCalls == ["jwt-1", "jwt-1"]) // initial connect, then the reconnect
        let sleepCalls = clock.sleepCalls
        #expect(sleepCalls == [1]) // the first backoff step
        let startCount = await transport.startCallCount
        #expect(startCount == 2) // resumed animating re-shows the page
    }

    @Test func exhaustingFiveReconnectAttemptsFallsBackAndDisconnects() async throws {
        let server = await readyServer()
        let transport = FakeSceneTransport()
        await transport.onConnect { _, attempt in
            if attempt == 1 { return "session-1" }
            throw ServerError.upstream("still down")
        }
        let clock = FakeSessionClock(now: t0)
        let controller = SessionController(server: server, transport: transport, clock: clock)
        await controller.warmUp()
        await controller.reportDisconnected("ICE dropped")

        // 5 reconnect attempts, each scheduled back-to-back by the fake clock's instant sleep.
        for _ in 0..<6 {
            try await settle()
        }

        let state = await controller.state
        #expect(state.phase == .fallback)
        let disconnectCount = await transport.disconnectCallCount
        #expect(disconnectCount == 1)
        let sleepCalls = clock.sleepCalls
        #expect(sleepCalls == [1, 2, 4, 8, 16])
    }

    @Test func killCancelsAnyPendingReconnectAndDisconnects() async throws {
        let server = await readyServer()
        let transport = FakeSceneTransport()
        await transport.onConnect { _, attempt in
            if attempt == 1 { return "session-1" }
            throw ServerError.upstream("still down")
        }
        let clock = FakeSessionClock(now: t0)
        let controller = SessionController(server: server, transport: transport, clock: clock)
        await controller.warmUp()
        await controller.reportDisconnected("ICE dropped")

        await controller.kill()
        try await settle()
        try await settle()

        let state = await controller.state
        #expect(state.phase == .killed)
        let connectCallsAfterKill = await transport.connectCalls.count
        try await settle()
        let connectCallsLater = await transport.connectCalls.count
        #expect(connectCallsLater == connectCallsAfterKill) // no further reconnects after kill
    }

    @Test func creditsAccumulateAtTheStableRateWhileConnectedAndStopAfterKill() async throws {
        let server = await readyServer()
        let transport = FakeSceneTransport()
        let clock = FakeSessionClock(now: t0)
        let controller = SessionController(server: server, transport: transport, clock: clock)
        await controller.warmUp()

        let fiveMinutesLater = t0.addingTimeInterval(5 * 60)
        let credits = await controller.credits(at: fiveMinutesLater)
        #expect(abs(credits - 5 * 0.582) < 0.0001)

        await controller.kill()
        let creditsAfterKill = await controller.credits(at: fiveMinutesLater)
        #expect(creditsAfterKill == 0)
    }
}

/// R-30: an Orbis session must never be left running after KILL, and the server must know
/// every session so its cleanup can end leftovers.
struct SessionControllerTeardownTests {
    private let t0 = Date(timeIntervalSince1970: 2_000_000)

    private func readyServer() async -> FakePopServer {
        let server = FakePopServer()
        let expiresAt = t0.addingTimeInterval(3600).timeIntervalSince1970
        await server.onReactorMint { ReactorMintResponse(jwt: "jwt-1", expiresAt: expiresAt) }
        return server
    }

    @Test func reportsEachConnectedSessionToTheServer() async {
        let server = await readyServer()
        let controller = SessionController(server: server, transport: FakeSceneTransport(), clock: FakeSessionClock(now: t0))
        await controller.warmUp()
        #expect(await server.reportCalls == ["session-for-jwt-1"])
    }

    @Test func killAsksTheServerToEndLeftoverSessions() async {
        let server = await readyServer()
        let transport = FakeSceneTransport()
        let controller = SessionController(server: server, transport: transport, clock: FakeSessionClock(now: t0))
        await controller.warmUp()
        await controller.kill()
        #expect(await server.cleanupCallCount == 1)
        #expect(await transport.disconnectCallCount == 1)
    }

    @Test func killDuringAConnectDisconnectsTheConnectionWhenItLands() async throws {
        let server = await readyServer()
        let transport = FakeSceneTransport()
        await transport.onConnect { jwt, _ in
            try await Task.sleep(for: .milliseconds(150))
            return "session-for-\(jwt)"
        }
        let controller = SessionController(server: server, transport: transport, clock: FakeSessionClock(now: t0))
        let warming = Task { await controller.warmUp() }
        try await Task.sleep(for: .milliseconds(40))
        await controller.kill()
        await warming.value

        #expect(await controller.state.phase == .killed)
        #expect(await transport.disconnectCallCount >= 1)
        #expect(await controller.credits() == 0)
    }

    @Test func killDuringAReconnectDisconnectsTheLateConnection() async throws {
        let server = await readyServer()
        let transport = FakeSceneTransport()
        await transport.onConnect { jwt, attempt in
            if attempt > 1 { try await Task.sleep(for: .milliseconds(150)) }
            return "session-for-\(jwt)"
        }
        let controller = SessionController(server: server, transport: transport, clock: FakeSessionClock(now: t0))
        await controller.warmUp()
        await controller.reportDisconnected("ICE dropped")
        try await Task.sleep(for: .milliseconds(40))
        let disconnectsBeforeKill = await transport.disconnectCallCount
        await controller.kill()
        try await Task.sleep(for: .milliseconds(250))

        #expect(await controller.state.phase == .killed)
        #expect(await transport.disconnectCallCount > disconnectsBeforeKill)
    }
}

/// Overlapping page flows on one session (a turn or revision during the ~1.6 s prepare):
/// the newest generation wins, an older one ends as superseded without touching the
/// session's phase, and a real stage failure leaves the session ready for the next page.
struct SessionControllerPageFlowTests {
    private let t0 = Date(timeIntervalSince1970: 3_000_000)

    private func readyController(_ transport: FakeSceneTransport) async -> SessionController {
        let server = FakePopServer()
        let expiresAt = t0.addingTimeInterval(3600).timeIntervalSince1970
        await server.onReactorMint { ReactorMintResponse(jwt: "jwt-1", expiresAt: expiresAt) }
        let controller = SessionController(server: server, transport: transport, clock: FakeSessionClock(now: t0))
        await controller.warmUp()
        return controller
    }

    @Test func aNewerPageDuringPrepareSupersedesTheOlderOneWhichNeverStarts() async throws {
        let transport = FakeSceneTransport()
        await transport.onPrepare { _, _, generation in
            if generation == 1 { try await Task.sleep(for: .milliseconds(120)) }
        }
        let controller = await readyController(transport)

        let older = Task { await controller.animate(page: 1, still: Data([1]), prompt: "one", generation: 1) }
        try await Task.sleep(for: .milliseconds(30))
        let newer = await controller.animate(page: 2, still: Data([2]), prompt: "two", generation: 2)
        let olderOutcome = await older.value

        #expect(newer == .started)
        #expect(olderOutcome == .superseded)
        #expect(await transport.startGenerations == [2])
        #expect(await controller.state.phase == .animating(page: 2))
    }

    @Test func aSupersededErrorFromTheTransportIsNotAStageFailure() async {
        let transport = FakeSceneTransport()
        await transport.onPrepare { _, _, _ in throw SceneTransportError.superseded }
        let controller = await readyController(transport)

        let outcome = await controller.animate(page: 1, still: Data(), prompt: "p", generation: 1)

        #expect(outcome == .superseded)
        #expect(await controller.state.phase == .animating(page: 1))
        #expect(await transport.connectCalls.count == 1) // no reconnect ladder
    }

    @Test func aRealStageFailureReportsFailedAndLeavesTheSessionReady() async throws {
        let transport = FakeSceneTransport()
        await transport.onStart { _ in throw ServerError.upstream("generation_started did not arrive") }
        let controller = await readyController(transport)

        let outcome = await controller.animate(page: 1, still: Data(), prompt: "p", generation: 1)
        try await Task.sleep(for: .milliseconds(30))

        guard case .failed = outcome else {
            Issue.record("expected failed, got \(outcome)")
            return
        }
        #expect(await controller.state.phase == .ready)
        #expect(await transport.connectCalls.count == 1)
        await transport.onStart { _ in }
        #expect(await controller.animate(page: 1, still: Data(), prompt: "p", generation: 2) == .started)
    }

    @Test func anOlderFlowFailingAfterANewerOneBeganDoesNotResetTheSession() async throws {
        let transport = FakeSceneTransport()
        await transport.onPrepare { _, _, generation in
            if generation == 1 {
                try await Task.sleep(for: .milliseconds(120))
                throw ServerError.upstream("set_image: rejected")
            }
        }
        let controller = await readyController(transport)

        let older = Task { await controller.animate(page: 1, still: Data(), prompt: "one", generation: 1) }
        try await Task.sleep(for: .milliseconds(30))
        #expect(await controller.animate(page: 2, still: Data(), prompt: "two", generation: 2) == .started)
        #expect(await older.value == .superseded)
        #expect(await controller.state.phase == .animating(page: 2))
    }

    @Test func aPageShownBeforeTheSessionIsConnectedIsReportedNotReady() async {
        let transport = FakeSceneTransport()
        let controller = SessionController(server: FakePopServer(), transport: transport, clock: FakeSessionClock(now: t0))

        let outcome = await controller.animate(page: 0, still: Data(), prompt: "p", generation: 1)

        #expect(outcome == .notReady)
        #expect(await transport.prepareCalls.isEmpty)
    }
}
