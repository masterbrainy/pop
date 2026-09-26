import Foundation
@testable import PopKit

/// A scriptable `SceneTransport` for `SessionController` tests.
actor FakeSceneTransport: SceneTransport {
    /// `attempt` is this call's 1-based index, so a test can make the Nth connect fail
    /// without needing its own external counter.
    var connectHandler: (@Sendable (_ jwt: String, _ attempt: Int) async throws -> String) = { jwt, _ in "session-for-\(jwt)" }
    var prepareHandler: (@Sendable (Data, String) async throws -> Void)?
    var startHandler: (@Sendable () async throws -> Void)?

    private(set) var connectCalls: [String] = []
    private(set) var prepareCalls: [(still: Data, prompt: String)] = []
    private(set) var startCallCount = 0
    private(set) var disconnectCallCount = 0

    func connect(jwt: String) async throws -> String {
        connectCalls.append(jwt)
        return try await connectHandler(jwt, connectCalls.count)
    }

    func prepare(still: Data, prompt: String) async throws {
        prepareCalls.append((still, prompt))
        try await prepareHandler?(still, prompt)
    }

    func start() async throws {
        startCallCount += 1
        try await startHandler?()
    }

    func disconnect() async {
        disconnectCallCount += 1
    }

    func onConnect(_ handler: @escaping @Sendable (_ jwt: String, _ attempt: Int) async throws -> String) {
        connectHandler = handler
    }

    func onPrepare(_ handler: @escaping @Sendable (Data, String) async throws -> Void) {
        prepareHandler = handler
    }
}

/// A `SessionClock` that never really sleeps, so backoff tests run instantly. It
/// still records every requested wait and advances its own `now()`.
///
/// Not thread-safe by construction — safe here only because `SessionController`
/// (the sole caller) is an actor that awaits every clock access in turn, and tests
/// read `sleepCalls` only after those awaits have already completed.
final class FakeSessionClock: SessionClock, @unchecked Sendable {
    private var currentTime: Date
    private(set) var sleepCalls: [TimeInterval] = []

    init(now: Date) {
        self.currentTime = now
    }

    func now() -> Date {
        currentTime
    }

    func sleep(for seconds: TimeInterval) async throws {
        sleepCalls.append(seconds)
        currentTime = currentTime.addingTimeInterval(seconds)
    }
}
