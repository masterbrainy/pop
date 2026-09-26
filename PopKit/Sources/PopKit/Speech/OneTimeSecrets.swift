import Foundation

/// Mints short-lived secrets ahead of need, so a mic tap doesn't wait on the server (the
/// `stt-token` secret lasts about 10 minutes). Each secret is handed out once, for one
/// connection; one within `margin` of expiring is replaced with a fresh one.
public actor OneTimeSecrets<Secret: Sendable> {
    private let mint: @Sendable () async throws -> Secret
    private let expiry: @Sendable (Secret) -> Date
    private let now: @Sendable () -> Date
    private let margin: TimeInterval
    private let refillsAfterTake: Bool
    /// The next secret: minting, minted, or failed.
    private var next: Task<Secret, any Error>?

    public init(margin: TimeInterval = 60, refillsAfterTake: Bool = true, now: @escaping @Sendable () -> Date = Date.init,
                expiry: @escaping @Sendable (Secret) -> Date, mint: @escaping @Sendable () async throws -> Secret) {
        self.margin = margin
        self.refillsAfterTake = refillsAfterTake
        self.now = now
        self.expiry = expiry
        self.mint = mint
    }

    /// Starts minting the next secret, unless one is already minting or minted.
    public func prefetch() {
        guard next == nil else { return }
        let mint = mint
        next = Task { try await mint() }
    }

    /// Waits for the prefetched secret to be minted; `true` if it was.
    public func waitForPrefetch() async -> Bool {
        guard let next else { return false }
        return (try? await next.value) != nil
    }

    /// A secret nobody else has had: the prefetched one if it minted and is still fresh,
    /// otherwise a new one. Starts minting the one after when `refillsAfterTake`.
    public func take() async throws -> Secret {
        let prefetched = next
        next = nil
        defer { if refillsAfterTake { prefetch() } }
        if let prefetched, let secret = try? await prefetched.value, isFresh(secret) {
            return secret
        }
        return try await mint()
    }

    private func isFresh(_ secret: Secret) -> Bool {
        expiry(secret).timeIntervalSince(now()) > margin
    }
}
