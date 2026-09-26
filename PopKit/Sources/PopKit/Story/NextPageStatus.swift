import Foundation

/// What the "next page" banner and the corner arrow say about the page behind (P-04), so a
/// direction is acknowledged at once and a rebuild is visible until its words land.
public enum NextPageStatus: Equatable, Sendable {
    /// No page follows: the story is just starting, or this is the ending.
    case none
    /// The page behind is being written; a turn waits for its words.
    case writing
    /// A direction is re-writing the page behind. A turn now shows the page behind as it was
    /// (when it has words) and the direction moves on to the page after (PRD S7).
    case rewriting(direction: String, canTurn: Bool)
    /// The page behind has its words; `rewritten` when a direction wrote it.
    case ready(rewritten: Bool)

    /// Whether a turn opens the page behind now.
    public var canTurn: Bool {
        switch self {
        case .none, .writing: false
        case let .rewriting(_, canTurn): canTurn
        case .ready: true
        }
    }

    /// - Parameters:
    ///   - direction: the latest direction while one is being written (or queued), else nil.
    ///   - rewrittenPageId: the id of the last page behind a direction wrote.
    public static func of(
        current: PageContent?, isEnding: Bool, pendingNext: PageContent?, direction: String?, rewrittenPageId: UUID?
    ) -> NextPageStatus {
        guard let current, !current.text.isEmpty, !isEnding else { return .none }
        let behind = pendingNext.flatMap { $0.text.isEmpty ? nil : $0 }
        if let direction { return .rewriting(direction: direction, canTurn: behind != nil) }
        guard let behind else { return .writing }
        return .ready(rewritten: behind.id == rewrittenPageId)
    }
}
