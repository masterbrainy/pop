import Foundation

/// One version of one page: what a picture, motion prompt or pop-up layers were made for.
public struct PageKey: Hashable, Sendable {
    public let id: UUID
    public let version: Int

    public init(id: UUID, version: Int) {
        self.id = id
        self.version = version
    }
}

extension PageContent {
    public var key: PageKey { PageKey(id: id, version: version) }
}

/// Where a page the story engine just wrote goes (P-04).
public enum PagePlacement: Equatable, Sendable {
    /// It filled the empty page on screen (the story is just starting).
    case onScreen(PageContent)
    /// It's a page ahead of the one on screen. `replacing` lists the page it replaced at that
    /// index and every page ahead after it (they followed the old page, so they're stale);
    /// their picture work can stop.
    case behind(PageContent, replacing: [PageContent])
    /// It was for a page the reader has already seen, or for a page too far ahead (or one whose
    /// page before it isn't written yet).
    case dropped
}

/// The pages of a book being made, plus the pages built ahead of the one on screen (P-04),
/// in order: `ahead[0]` is the next page, `ahead[1]` the one after it, and so on.
/// Results are routed by page id and version, never by index, so a late picture can't land on
/// the page that replaced its own, and a change made to the latest copy keeps whatever else
/// arrived meanwhile (a clip, pop-up layers).
public struct DraftPages: Equatable, Sendable {
    public let pages: [PageContent]
    public let ahead: [PageContent]

    public init(pages: [PageContent], ahead: [PageContent]) {
        self.pages = pages
        self.ahead = ahead
    }

    public init(pages: [PageContent], pendingNext: PageContent?) {
        self.init(pages: pages, ahead: pendingNext.map { [$0] } ?? [])
    }

    /// The page right behind the one on screen, which a turn opens.
    public var pendingNext: PageContent? { ahead.first }

    public func page(id: UUID) -> PageContent? {
        pages.first { $0.id == id } ?? ahead.first { $0.id == id }
    }

    /// Places a freshly written page. An empty page on screen takes it; otherwise it becomes a
    /// page ahead, up to `lookahead` pages past `currentIndex`, right after the pages ahead of
    /// it. Replacing a page ahead also drops every page ahead after it. A page the reader has
    /// seen never changes. The placed page's version is above the one it replaces, so their
    /// pictures never share a file name.
    public func placing(_ written: PageContent, currentIndex: Int?, lookahead: Int = 1) -> (pages: DraftPages, placement: PagePlacement) {
        if let position = pages.firstIndex(where: { $0.index == written.index }) {
            let occupant = pages[position]
            guard occupant.text.isEmpty else { return (self, .dropped) }
            let placed = written.succeeding(occupant)
            var updated = pages
            updated[position] = placed
            return (DraftPages(pages: updated, ahead: ahead), .onScreen(placed))
        }
        guard let currentIndex else { return (self, .dropped) }
        let slot = written.index - currentIndex - 1
        guard slot >= 0, slot < lookahead, slot <= ahead.count else { return (self, .dropped) }
        let replaced = Array(ahead[slot...])
        let placed = written.succeeding(replaced.first)
        return (DraftPages(pages: pages, ahead: Array(ahead[..<slot]) + [placed]), .behind(placed, replacing: replaced))
    }

    /// Changes the page with this id (and this version, when given), in the book or ahead of it.
    /// Nil when no page has this id any more (it was replaced) or it's at another version.
    public func updatingPage(
        id: UUID, version: Int? = nil, _ change: (PageContent) -> PageContent
    ) -> (pages: DraftPages, page: PageContent)? {
        if let slot = ahead.firstIndex(where: { $0.id == id }) {
            guard version.map({ $0 == ahead[slot].version }) ?? true else { return nil }
            let changed = change(ahead[slot])
            var updated = ahead
            updated[slot] = changed
            return (DraftPages(pages: pages, ahead: updated), changed)
        }
        guard let position = pages.firstIndex(where: { $0.id == id }),
              version.map({ $0 == pages[position].version }) ?? true
        else { return nil }
        let changed = change(pages[position])
        var updated = pages
        updated[position] = changed
        return (DraftPages(pages: updated, ahead: ahead), changed)
    }

    /// A turn onto the next page: it joins the book, and the rest of the pages ahead move up.
    public func turning() -> DraftPages? {
        guard let next = ahead.first else { return nil }
        return DraftPages(pages: pages + [next], ahead: Array(ahead.dropFirst()))
    }
}

private extension PageContent {
    /// This page, numbered after `occupant` (the page it replaces at the same index).
    func succeeding(_ occupant: PageContent?) -> PageContent {
        let next = max(version, (occupant?.version ?? 0) + 1)
        return PageContent(id: id, index: index, version: next, text: text, artPrompt: artPrompt, stillPath: stillPath,
                           layers: layers, motion: motion, clipPath: clipPath, question: question)
    }
}
