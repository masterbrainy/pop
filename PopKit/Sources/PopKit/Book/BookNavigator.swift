public enum BookMode: Sendable, Equatable {
    /// Making the book: turning past the last page starts a new page (PRD §7 step 2).
    case creating
    /// Showing a saved book: the last page stays put.
    case reading
}

public enum TurnOutcome: Sendable, Equatable {
    case turned(to: Int)
    case newPage(index: Int)
    case atEnd
}

/// Which page is showing, and what a turn does. Values only; each move returns a new navigator.
public struct BookNavigator: Sendable, Equatable {
    public let pageCount: Int
    public let mode: BookMode
    public let index: Int

    public init(pageCount: Int, mode: BookMode, index: Int = 0) {
        let count = mode == .creating ? max(pageCount, 1) : max(pageCount, 0)
        self.pageCount = count
        self.mode = mode
        self.index = min(max(index, 0), max(count - 1, 0))
    }

    public func turningForward() -> (BookNavigator, TurnOutcome) {
        if index + 1 < pageCount {
            return (BookNavigator(pageCount: pageCount, mode: mode, index: index + 1), .turned(to: index + 1))
        }
        guard mode == .creating else { return (self, .atEnd) }
        return (BookNavigator(pageCount: pageCount + 1, mode: mode, index: index + 1), .newPage(index: index + 1))
    }

    public func turningBack() -> BookNavigator {
        BookNavigator(pageCount: pageCount, mode: mode, index: index - 1)
    }

    public func openedFromCover() -> BookNavigator {
        BookNavigator(pageCount: pageCount, mode: mode, index: 0)
    }

    public func with(pageCount: Int) -> BookNavigator {
        BookNavigator(pageCount: pageCount, mode: mode, index: index)
    }
}
