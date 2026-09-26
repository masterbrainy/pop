import Foundation
import Testing
@testable import PopKit

/// Covers `OneTimeSecrets`: the speech secret is minted before the mic is tapped, so
/// listening starts without waiting on the server. Each secret opens one connection, and
/// one close to expiry is replaced.
struct OneTimeSecretsTests {
    struct Secret: Sendable, Equatable {
        let value: String
        let expiresAt: Date
    }

    /// Mints "s1", "s2", … each valid for `lifetime` from the fake clock's time, or fails.
    actor Mint {
        private(set) var calls = 0
        var failNext = false
        var now: Date
        let lifetime: TimeInterval

        init(now: Date, lifetime: TimeInterval = 600) {
            self.now = now
            self.lifetime = lifetime
        }

        func next() throws -> Secret {
            calls += 1
            if failNext {
                failNext = false
                throw URLError(.notConnectedToInternet)
            }
            return Secret(value: "s\(calls)", expiresAt: now.addingTimeInterval(lifetime))
        }

        func failTheNextMint() { failNext = true }
        func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }

    /// A clock the tests move by hand.
    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var date: Date
        init(_ date: Date) { self.date = date }
        var now: Date { lock.withLock { date } }
        func advance(_ seconds: TimeInterval) { lock.withLock { date = date.addingTimeInterval(seconds) } }
    }

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func secrets(_ mint: Mint, clock: Clock, refills: Bool = false) -> OneTimeSecrets<Secret> {
        OneTimeSecrets(margin: 60, refillsAfterTake: refills, now: { clock.now }, expiry: \.expiresAt) { try await mint.next() }
    }

    @Test func aPrefetchedSecretIsHandedOutWithoutAnotherMint() async throws {
        let mint = Mint(now: t0)
        let secrets = secrets(mint, clock: Clock(t0))

        await secrets.prefetch()
        let secret = try await secrets.take()

        #expect(secret.value == "s1")
        #expect(await mint.calls == 1)
    }

    @Test func prefetchingTwiceMintsOnce() async throws {
        let mint = Mint(now: t0)
        let secrets = secrets(mint, clock: Clock(t0))

        await secrets.prefetch()
        await secrets.prefetch()
        _ = try await secrets.take()

        #expect(await mint.calls == 1)
    }

    @Test func aSecretIsNeverHandedOutTwice() async throws {
        let mint = Mint(now: t0)
        let secrets = secrets(mint, clock: Clock(t0))
        await secrets.prefetch()

        let first = try await secrets.take()
        let second = try await secrets.take()

        #expect(first.value != second.value)
    }

    @Test func takingWithoutAPrefetchMintsOne() async throws {
        let mint = Mint(now: t0)
        let secrets = secrets(mint, clock: Clock(t0))

        let secret = try await secrets.take()

        #expect(secret.value == "s1")
    }

    @Test func aSecretCloseToExpiryIsReplacedWithAFreshOne() async throws {
        let mint = Mint(now: t0)
        let clock = Clock(t0)
        let secrets = secrets(mint, clock: clock)
        await secrets.prefetch()
        _ = await secrets.waitForPrefetch()

        clock.advance(550)
        await mint.advance(550)
        let secret = try await secrets.take()

        #expect(secret.value == "s2")
        #expect(secret.expiresAt == t0.addingTimeInterval(1_150))
    }

    @Test func aFailedPrefetchIsMintedAgainOnTake() async throws {
        let mint = Mint(now: t0)
        await mint.failTheNextMint()
        let secrets = secrets(mint, clock: Clock(t0))
        await secrets.prefetch()

        let secret = try await secrets.take()

        #expect(secret.value == "s2")
    }

    @Test func aFailedMintOnTakeThrows() async {
        let mint = Mint(now: t0)
        let secrets = secrets(mint, clock: Clock(t0))
        await mint.failTheNextMint()

        await #expect(throws: URLError.self) { try await secrets.take() }
    }

    @Test func takingRefillsForTheNextConnection() async throws {
        let mint = Mint(now: t0)
        let secrets = secrets(mint, clock: Clock(t0), refills: true)
        await secrets.prefetch()

        _ = try await secrets.take()
        _ = await secrets.waitForPrefetch()
        #expect(await mint.calls == 2)

        let second = try await secrets.take()
        #expect(second.value == "s2")
    }
}
