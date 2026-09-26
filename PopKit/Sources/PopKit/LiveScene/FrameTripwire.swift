/// The frame tripwire (ROADMAP Phase 3): a frame sampled from the live video goes through
/// image moderation, and a flagged frame sends the page back to its still. The still and the
/// motion prompt were already moderated, so a failed check leaves the video playing and is
/// only logged.
public struct FrameTripwire: Sendable {
    public enum Verdict: Equatable, Sendable {
        case clear
        case flagged([String])
        case unchecked(String)

        public var isFlagged: Bool {
            if case .flagged = self { return true }
            return false
        }
    }

    /// While a page's clip records (its first `clipSeconds`), a frame is checked every
    /// `clipCheckSpacing`, so no part of the saved clip goes unchecked (R-38); after that,
    /// one every `interval`.
    public static let clipCheckSpacing: Duration = .seconds(3)
    public static let clipSeconds = 10
    public static let interval: Duration = .seconds(15)
    /// The sampled frame's long side, in pixels.
    public static let maxSide = 512

    private let server: any PopServer

    public init(server: any PopServer) {
        self.server = server
    }

    /// How long to wait before check number `index` (0 is the first) on a page.
    public static func delay(beforeCheck index: Int) -> Duration {
        let checksDuringClip = Int(Duration.seconds(clipSeconds + 2) / clipCheckSpacing)
        return index < checksDuringClip ? clipCheckSpacing : interval
    }

    public func check(base64: String, mimeType: String) async -> Verdict {
        do {
            let result = try await server.moderate(.image(base64: base64, mimeType: mimeType))
            return result.flagged ? .flagged(result.categories) : .clear
        } catch {
            return .unchecked(String(describing: error))
        }
    }
}
