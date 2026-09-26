/// What to do with a page's recorded clip once its sampled frames have been moderated.
public enum ClipVerdict: Equatable, Sendable {
    /// Every frame came back clear, or the page was watched live and the live tripwire
    /// already covered it: the clip can be attached to the page.
    case attach
    /// At least one frame was flagged; the categories of every flagged frame, each once.
    case flagged([String])
    /// The clip couldn't be fully checked on a page nobody has seen, so it isn't attached.
    case unchecked(String)

    /// Combines the per-frame verdicts. Any flagged frame flags the clip. A page nobody has
    /// seen fails closed when a frame couldn't be checked; a page seen live was already
    /// covered by the live tripwire, so it attaches. No frames at all is always unchecked.
    public static func decide(_ verdicts: [FrameTripwire.Verdict], pageWasSeenLive: Bool) -> ClipVerdict {
        if verdicts.contains(where: \.isFlagged) {
            return .flagged(flaggedCategories(verdicts))
        }
        guard !verdicts.isEmpty else { return .unchecked("no frames") }
        if let reason = firstUncheckedReason(verdicts) {
            return pageWasSeenLive ? .attach : .unchecked(reason)
        }
        return .attach
    }

    private static func flaggedCategories(_ verdicts: [FrameTripwire.Verdict]) -> [String] {
        let all = verdicts.flatMap { verdict -> [String] in
            if case let .flagged(categories) = verdict { return categories }
            return []
        }
        return all.reduce(into: [String]()) { unique, category in
            if !unique.contains(category) { unique.append(category) }
        }
    }

    private static func firstUncheckedReason(_ verdicts: [FrameTripwire.Verdict]) -> String? {
        verdicts.lazy.compactMap { verdict -> String? in
            if case let .unchecked(reason) = verdict { return reason }
            return nil
        }.first
    }
}
