import Foundation

/// Where one version of a page's picture is.
public enum PictureState: Equatable, Sendable {
    case painting
    /// The still is on disk.
    case stored
    /// Moderation turned the picture away twice (IMP-10); no picture is coming.
    case unavailable
    /// The picture failed, or missed its deadline; the page shows without it (a still that
    /// lands later still shows).
    case gaveUp
}

/// Where one version of a page's motion prompt is.
public enum MotionState: Equatable, Sendable {
    case pending
    case ready
    case failed
}

/// "No page until painted": whether a page is good to show. A page shows only with its words
/// and its picture, or once its picture can't come (the imagine card). The page on screen
/// needs only its still; the page behind also waits for its motion prompt, but no longer than
/// `motionGrace` after its still, so a slow motion call never holds a turn. Pop-up layers are
/// never waited for.
public enum PageReadiness: Equatable, Sendable {
    case writing
    case painting
    case ready(picture: Bool)

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    /// - Parameters:
    ///   - picture: this version's picture state; a page that has a still counts as stored.
    ///   - stillStoredAt: when the still was stored; nil means long enough ago.
    ///   - requiresMotion: true for the page behind (it should come alive as it's shown).
    public static func of(
        page: PageContent?, picture: PictureState, motion: MotionState, stillStoredAt: Date?, now: Date,
        requiresMotion: Bool, motionGrace: TimeInterval = PaintDeadlines.motionGrace
    ) -> PageReadiness {
        guard let page, !page.text.isEmpty else { return .writing }
        let effective: PictureState = page.stillPath != nil ? .stored : picture
        switch effective {
        case .painting:
            return .painting
        case .unavailable, .gaveUp:
            return .ready(picture: false)
        case .stored:
            guard requiresMotion, motion == .pending, let stillStoredAt else { return .ready(picture: true) }
            return now.timeIntervalSince(stillStoredAt) >= motionGrace ? .ready(picture: true) : .painting
        }
    }
}

/// How long a page's picture is waited for. The `art` function spends at most
/// `serverArtBudget` on one picture (R-49), and a failed call is tried once more after
/// `artRetryDelay`. Page 1 fits one full call plus storing the still; the page behind (the
/// parent is still reading) fits the call and its retry. Past these the page shows with the
/// imagine card, and a still that lands later still shows.
public enum PaintDeadlines {
    public static let serverArtBudget: TimeInterval = 40
    public static let artRetryDelay: TimeInterval = 2
    /// Page 1, counted from its words landing.
    public static let firstPage: TimeInterval = 50
    /// The page behind, counted from when it starts painting (after the page on screen shows).
    public static let pageBehind: TimeInterval = 90
    /// The page behind waits this long after its still for its motion prompt.
    public static let motionGrace: TimeInterval = 8
    /// A scripted fold waits this long for the page behind (past its own deadline).
    public static let waitForPageBehind: TimeInterval = 100
    /// Page 1's left page adds "Almost there…" after this long.
    public static let firstPageSlow: TimeInterval = 20
}

/// "No page until prompted": where page 1 is. The book opens empty and waits for the parent's
/// opening prompt; nothing is written from the brief alone.
public enum OpeningState: Equatable, Sendable {
    case awaitingPrompt
    /// The prompt is in; the kid's drawing is still becoming the hero.
    case preparingHero
    case writing
    case painting
    case shown

    /// - Parameters:
    ///   - isWritingFirst: an opening prompt was sent and page 1 isn't back yet.
    ///   - heroPending: the kid's drawing is still becoming the hero.
    ///   - readiness: page 1's readiness.
    public static func of(current: PageContent?, isWritingFirst: Bool, heroPending: Bool, readiness: PageReadiness) -> OpeningState {
        if let current, !current.text.isEmpty {
            return readiness.isReady ? .shown : .painting
        }
        guard isWritingFirst else { return .awaitingPrompt }
        return heroPending ? .preparingHero : .writing
    }

    /// What the left page says while page 1 isn't shown; nil once it is.
    public func leftPage(prompt: String?, isSlow: Bool) -> String? {
        let quoted = prompt.map { "\n\n“\($0)”" } ?? ""
        switch self {
        case .awaitingPrompt: return "How does the story begin? Say it or type it below."
        case .preparingHero: return "Getting your hero ready…" + quoted
        case .writing, .painting: return "Making your first page…" + quoted + (isSlow ? "\n\nAlmost there…" : "")
        case .shown: return nil
        }
    }
}
