/// The kid's reading level (PRD §8.7). It sets the story's per-page limits and the
/// smallest text size on the page (PRD P1).
public enum ReadingLevel: String, Codable, CaseIterable, Sendable {
    case listener
    case earlyReader = "early_reader"
    case reader

    public var title: String {
        switch self {
        case .listener: "Listener"
        case .earlyReader: "Early reader"
        case .reader: "Reader"
        }
    }

    public var ages: String {
        switch self {
        case .listener: "3–4"
        case .earlyReader: "5–6"
        case .reader: "7–8"
        }
    }

    public var maxWordsPerPage: Int {
        switch self {
        case .listener: 15
        case .earlyReader: 30
        case .reader: 60
        }
    }

    public var sentencesPerPage: ClosedRange<Int> {
        switch self {
        case .listener: 1...2
        case .earlyReader: 2...3
        case .reader: 1...5
        }
    }

    /// Points; the page text is never smaller than this.
    public var minimumTextSize: Double {
        switch self {
        case .listener: 32
        case .earlyReader: 28
        case .reader: 24
        }
    }
}
