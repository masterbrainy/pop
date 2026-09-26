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
        await controller.animate(page: 2, still: still, prompt: "a fox sways")

        let state = await controller.state
        #expect(state.phase == .animating(page: 2))
        let prepareCalls = await transport.prepareCalls
        #expect(prepareCalls.count == 1 && prepareCalls[0].still == still && prepareCalls[0].prompt == "a fox sways")
        let startCount = await transport.startCallCount
        #expect(startCount == 1)
    }

    @Test func aDropReconnectsAndResumesTheSamePageUsingTheFakeClockWithNoRealDelay() async throws {
        let server = await readyServer()
        let transport = FakeSceneTransport()
        let clock = FakeSessionClock(now: t0)
        let controller = SessionController(server: server, transport: transport, clock: clock)
        await controller.warmUp()
        await controller.animate(page: 4, still: Data(), prompt: "prompt")

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
