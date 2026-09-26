import PopKit
import SwiftUI

/// The open book: text on the left page, picture on the right (PRD §8.2), one page per
/// screen half through `ArrangementView`. The hinge only drives effects (curl, pop-up),
/// never layout (PRD H4). While creating, the story controls sit under the text.
struct SpreadView<Controls: View>: View {
    let page: PageContent?
    let pageNumber: Int
    let level: ReadingLevel
    let curl: Double
    var popDepth: Double = 0
    var live: LivePageController? = nil
    var replaysClips = false
    var highlight: NSRange? = nil
    @ViewBuilder var controls: () -> Controls

    var body: some View {
        ArrangementView {
            ZStack(alignment: .bottom) {
                TextPageView(text: page?.text ?? "", level: level, pageNumber: pageNumber, highlight: highlight)
                    .id(page?.id)
                    .transition(.opacity)
                controls()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
            }
        } secondary: {
            ArtPageView(page: page, live: live, popDepth: popDepth, replaysClips: replaysClips)
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

extension SpreadView where Controls == EmptyView {
    init(page: PageContent?, pageNumber: Int, level: ReadingLevel, curl: Double, popDepth: Double = 0,
         live: LivePageController? = nil, replaysClips: Bool = false, highlight: NSRange? = nil) {
        self.init(page: page, pageNumber: pageNumber, level: level, curl: curl, popDepth: popDepth,
                  live: live, replaysClips: replaysClips, highlight: highlight) { EmptyView() }
    }
}
