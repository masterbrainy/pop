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
    /// It's the new page behind the one on screen, replacing `replacing`, whose picture work can stop.
    case behind(PageContent, replacing: PageContent?)
    /// It was for a page the reader has already seen, or for a page that isn't the one behind.
    case dropped
}

/// The pages of a book being made, plus the page built behind the one on screen (P-04).
/// Results are routed by page id and version, never by index, so a late picture can't land on
/// the page that replaced its own, and a change made to the latest copy keeps whatever else
/// arrived meanwhile (a clip, pop-up layers).
public struct DraftPages: Equatable, Sendable {
    public let pages: [PageContent]
    public let pendingNext: PageContent?

    public init(pages: [PageContent], pendingNext: PageContent?) {
        self.pages = pages
        self.pendingNext = pendingNext
    }

    public func page(id: UUID) -> PageContent? {
        pages.first { $0.id == id } ?? (pendingNext?.id == id ? pendingNext : nil)
    }

    /// Places a freshly written page. An empty page on screen takes it; otherwise it becomes the
    /// page behind (`currentIndex + 1`). A page the reader has seen never changes. The placed
    /// page's version is above the one it replaces, so their pictures never share a file name.
    public func placing(_ written: PageContent, currentIndex: Int?) -> (pages: DraftPages, placement: PagePlacement) {
        if let position = pages.firstIndex(where: { $0.index == written.index }) {
            let occupant = pages[position]
            guard occupant.text.isEmpty else { return (self, .dropped) }
            let placed = written.succeeding(occupant)
            var updated = pages
            updated[position] = placed
            return (DraftPages(pages: updated, pendingNext: pendingNext), .onScreen(placed))
        }
        guard let currentIndex, written.index == currentIndex + 1 else { return (self, .dropped) }
        let replaced = pendingNext
        let placed = written.succeeding(replaced?.index == written.index ? replaced : nil)
        return (DraftPages(pages: pages, pendingNext: placed), .behind(placed, replacing: replaced))
    }

    /// Changes the page with this id (and this version, when given), in the book or behind it.
    /// Nil when no page has this id any more (it was replaced) or it's at another version.
    public func updatingPage(
        id: UUID, version: Int? = nil, _ change: (PageContent) -> PageContent
    ) -> (pages: DraftPages, page: PageContent)? {
        if let pending = pendingNext, pending.id == id {
            guard version.map({ $0 == pending.version }) ?? true else { return nil }
            let changed = change(pending)
            return (DraftPages(pages: pages, pendingNext: changed), changed)
        }
        guard let position = pages.firstIndex(where: { $0.id == id }),
              version.map({ $0 == pages[position].version }) ?? true
        else { return nil }
        let changed = change(pages[position])
        var updated = pages
        updated[position] = changed
        return (DraftPages(pages: updated, pendingNext: pendingNext), changed)
    }
}

private extension PageContent {
    /// This page, numbered after `occupant` (the page it replaces at the same index).
    func succeeding(_ occupant: PageContent?) -> PageContent {
        let next = max(version, (occupant?.version ?? 0) + 1)
        return renumbered(index: index, version: next)
    }
}
