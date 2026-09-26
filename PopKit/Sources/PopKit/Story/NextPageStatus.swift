import Foundation

/// What the "next page" banner and the corner arrow say about the page behind (P-04), so a
/// direction is acknowledged at once and a rebuild is visible until its page is ready. A page
/// behind opens only once it's painted ("no page until painted", `PageReadiness`).
public enum NextPageStatus: Equatable, Sendable {
    /// No page follows: the story is just starting, the page on screen isn't shown yet, or
    /// this is the ending.
    case none
    /// The page behind is being written; a turn waits for its words.
    case writing
    /// The page behind has its words; a turn waits for its picture.
    case painting
    /// A direction is re-writing the page behind. While the direction's words are coming, a
    /// turn shows the page behind as it was, if that one is painted, and the direction moves
    /// on to the page after (PRD S7). Once they land, it lasts until the rewritten page is ready.
    case rewriting(direction: String, canTurn: Bool)
    /// The page behind is ready; `rewritten` when a direction wrote it.
    case ready(rewritten: Bool)

    /// Whether a turn opens the page behind now.
    public var canTurn: Bool {
        switch self {
        case .none, .writing, .painting: false
        case let .rewriting(_, canTurn): canTurn
        case .ready: true
        }
    }

    /// - Parameters:
    ///   - currentShown: the page on screen is shown (page 1 waits for its picture).
    ///   - behindReady: the page behind has its words and picture (`PageReadiness`).
    ///   - direction: the latest direction while one is being written (or queued), else nil.
    ///   - rewrittenPageId: the id of the last page behind a direction wrote.
    ///   - lastDirection: the direction that wrote it, said while it's still painting.
    public static func of(
        current: PageContent?, currentShown: Bool, isEnding: Bool, pendingNext: PageContent?, behindReady: Bool,
        direction: String?, rewrittenPageId: UUID?, lastDirection: String? = nil
    ) -> NextPageStatus {
        guard let current, !current.text.isEmpty, currentShown, !isEnding else { return .none }
        let behind = pendingNext.flatMap { $0.text.isEmpty ? nil : $0 }
        if let direction { return .rewriting(direction: direction, canTurn: behind != nil && behindReady) }
        guard let behind else { return .writing }
        let rewritten = behind.id == rewrittenPageId
        guard behindReady else { return rewritten ? .rewriting(direction: lastDirection ?? "", canTurn: false) : .painting }
        return .ready(rewritten: rewritten)
    }
}
