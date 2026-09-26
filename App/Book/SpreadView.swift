import PopKit
import SwiftUI

/// The open book: text on the left page, picture on the right (PRD §8.2), one page per
/// screen half through `ArrangementView`. The hinge only drives effects (curl), never
/// layout (PRD H4).
struct SpreadView: View {
    let page: PageContent?
    let pageNumber: Int
    let level: ReadingLevel
    let curl: Double

    var body: some View {
        ArrangementView {
            TextPageView(text: page?.text ?? "", level: level, pageNumber: pageNumber)
                .id(page?.id)
                .transition(.opacity)
        } secondary: {
            ArtPageView(page: page)
                .pageCurl(progress: curl)
                .id(page?.id)
                .transition(PageFlipTransition())
        }
        .arrangementViewStyle(.split)
        .background(Theme.paper)
        .animation(.easeInOut(duration: 0.45), value: page?.id)
        .ignoresSafeArea()
    }
}
