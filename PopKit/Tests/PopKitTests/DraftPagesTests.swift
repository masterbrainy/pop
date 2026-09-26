import Foundation
import Testing
@testable import PopKit

/// `DraftPages`: where a freshly written page goes (P-04), and results routed by page id and
/// version rather than by index, so a late picture can't land on the page that replaced it.
struct DraftPagesTests {
    private let shown = PageContent(index: 0, text: "Sara finds a kite.", artPrompt: "a kite", stillPath: "/p0.png", clipPath: "/p0.mov")

    private func written(_ index: Int, _ text: String = "The kite pulls her up.") -> PageContent {
        PageContent(index: index, text: text, artPrompt: "art \(index)")
    }

    @Test func aPageWrittenForTheEmptyPageOnScreenFillsItWithANewerVersion() {
        let empty = PageContent(index: 0, text: "")
        let draft = DraftPages(pages: [empty], pendingNext: nil)
        let page = written(0, "Sara finds a kite.")

        let (next, placement) = draft.placing(page, currentIndex: 0)

        guard case let .onScreen(placed) = placement else { Issue.record("expected onScreen, got \(placement)"); return }
        #expect(placed.id == page.id)
        #expect(placed.version > empty.version)
        #expect(next.pages == [placed])
        #expect(next.pendingNext == nil)
    }

    @Test func aPageWrittenForThePageBehindBecomesIt() {
        let draft = DraftPages(pages: [shown], pendingNext: nil)
        let page = written(1)

        let (next, placement) = draft.placing(page, currentIndex: 0)

        #expect(placement == .behind(page, replacing: []))
        #expect(next.pendingNext == page)
        #expect(next.pages == [shown])
    }

    @Test func aRewrittenPageBehindReplacesTheOldOneWithAHigherVersionSoItsArtNeverSharesAPath() {
        let old = written(1, "The kite flies.").with(stillPath: "/p1-old.png")
        let draft = DraftPages(pages: [shown], pendingNext: old)
        let page = written(1, "Snow starts to fall on the kite.")

        let (next, placement) = draft.placing(page, currentIndex: 0)

        guard case let .behind(placed, replacing) = placement else { Issue.record("expected behind, got \(placement)"); return }
        #expect(replacing == [old])
        #expect(placed.id == page.id)
        #expect(placed.version == old.version + 1)
        #expect(placed.stillPath == nil)
        #expect(next.pendingNext == placed)
    }

    @Test func aPageWrittenForAPageAlreadyShownIsDroppedAndThePageOnScreenNeverChanges() {
        let draft = DraftPages(pages: [shown], pendingNext: nil)

        let (next, placement) = draft.placing(written(0, "Something else."), currentIndex: 0)

        #expect(placement == .dropped)
        #expect(next == draft)
    }

    @Test func aPageWrittenForAnIndexThatIsNotThePageBehindIsDropped() {
        let behind = written(1)
        let draft = DraftPages(pages: [shown], pendingNext: behind)

        let (next, placement) = draft.placing(written(2), currentIndex: 0)

        #expect(placement == .dropped)
        #expect(next == draft)
    }

    @Test func aStillForThePageBehindLandsOnItByIdAndVersion() throws {
        let behind = written(1)
        let draft = DraftPages(pages: [shown], pendingNext: behind)

        let result = try #require(draft.updatingPage(id: behind.id, version: behind.version) { $0.with(stillPath: "/p1.png") })

        #expect(result.page.stillPath == "/p1.png")
        #expect(result.pages.pendingNext?.stillPath == "/p1.png")
        #expect(result.pages.pages == [shown])
    }

    @Test func aStillForAPageThatWasReplacedIsDroppedInsteadOfLandingOnTheNewPageAtTheSameIndex() {
        let old = written(1, "The kite flies.")
        let replacement = written(1, "Snow starts to fall.")
        let draft = DraftPages(pages: [shown], pendingNext: replacement)

        #expect(draft.updatingPage(id: old.id, version: old.version) { $0.with(stillPath: "/old.png") } == nil)
    }

    @Test func aStillForAnOlderVersionOfThePageIsDropped() {
        let behind = PageContent(index: 1, version: 3, text: "Snow.", artPrompt: "snow")
        let draft = DraftPages(pages: [shown], pendingNext: behind)

        #expect(draft.updatingPage(id: behind.id, version: 2) { $0.with(stillPath: "/v2.png") } == nil)
    }

    @Test func updatingAShownPageChangesOnlyThatFieldOnTheLatestCopy() throws {
        // Layers arrive while a clip is already attached: the clip must survive.
        let draft = DraftPages(pages: [shown], pendingNext: written(1))
        let layers = PageLayers(platePath: "/plate.png", cutouts: [])

        let result = try #require(draft.updatingPage(id: shown.id, version: shown.version) { $0.with(layers: layers) })

        #expect(result.page.layers == layers)
        #expect(result.page.clipPath == "/p0.mov")
        #expect(result.page.stillPath == "/p0.png")
        #expect(result.pages.pendingNext == draft.pendingNext)
    }

    @Test func updatingWithoutAVersionFindsThePageByIdAlone() throws {
        let draft = DraftPages(pages: [shown], pendingNext: nil)

        let result = try #require(draft.updatingPage(id: shown.id) { $0.with(clipPath: nil) })

        #expect(result.page.clipPath == nil)
        #expect(draft.page(id: shown.id) == shown)
        #expect(draft.page(id: UUID()) == nil)
    }

    // MARK: - Two pages ahead

    @Test func withALookaheadOfTwoThePageAfterTheNextOneIsKeptBehindIt() {
        let next = written(1, "The kite flies.")
        let draft = DraftPages(pages: [shown], ahead: [next])
        let later = written(2, "It lands in a tree.")

        let (result, placement) = draft.placing(later, currentIndex: 0, lookahead: 2)

        #expect(placement == .behind(later, replacing: []))
        #expect(result.ahead == [next, later])
        #expect(result.pendingNext == next)
    }

    @Test func aPageTwoAheadIsDroppedUntilThePageBeforeItIsWritten() {
        let draft = DraftPages(pages: [shown], ahead: [])

        let (result, placement) = draft.placing(written(2), currentIndex: 0, lookahead: 2)

        #expect(placement == .dropped)
        #expect(result == draft)
    }

    @Test func rewritingTheNextPageDropsThePagesAheadThatFollowedTheOldOne() {
        let oldNext = written(1, "The kite flies.")
        let oldLater = written(2, "It lands in a tree.")
        let draft = DraftPages(pages: [shown], ahead: [oldNext, oldLater])
        let rewrite = written(1, "Snow starts to fall on the kite.")

        let (result, placement) = draft.placing(rewrite, currentIndex: 0, lookahead: 2)

        guard case let .behind(placed, replacing) = placement else { Issue.record("expected behind, got \(placement)"); return }
        #expect(replacing == [oldNext, oldLater])
        #expect(result.ahead == [placed])
    }

    @Test func turningMovesTheNextPageIntoTheBookAndTheRestUp() {
        let next = written(1)
        let later = written(2)
        let draft = DraftPages(pages: [shown], ahead: [next, later])

        let turned = draft.turning()

        #expect(turned?.pages == [shown, next])
        #expect(turned?.ahead == [later])
    }

    @Test func updatingFindsAPageTwoAhead() {
        let later = written(2)
        let draft = DraftPages(pages: [shown], ahead: [written(1), later])

        let result = draft.updatingPage(id: later.id) { $0.with(stillPath: "/p2.png") }

        #expect(result?.pages.ahead.last?.stillPath == "/p2.png")
    }
}
