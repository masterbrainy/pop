import Foundation
import Testing
@testable import PopKit

/// Turning to the page behind may renumber it; it must stay the same page, so a loop or
/// layers made for it (keyed by page id and version) still belong to it.
struct PageReindexTests {
    @Test func renumberingAPageKeepsItsIdVersionAndMedia() {
        let layers = PageLayers(platePath: "plate.png", cutouts: [])
        let page = PageContent(index: 3, version: 2, text: "Hi", artPrompt: "art", stillPath: "s.png", layers: layers,
                               motion: MotionParts(scene: "a", motion: "b"), clipPath: "loop.mp4", question: "q")
        let moved = page.with(index: 2)
        #expect(moved.index == 2)
        #expect(moved.id == page.id)
        #expect(moved.version == 2)
        #expect(moved.clipPath == "loop.mp4")
        #expect(moved.layers == layers)
        #expect(moved.motion == page.motion)
        #expect(moved.question == "q")
    }
}
