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
    var pictureUnavailable = false
    /// What the left page says while there's no page to show (before page 1 is painted).
    var emptyText: String? = nil
    @ViewBuilder var controls: () -> Controls

    /// The co-pilot question shows while reading a book, not while making one.
    private var showsQuestion: Bool { live == nil }

    var body: some View {
        ArrangementView {
            ZStack(alignment: .bottom) {
                textPage
                    .id(page?.id)
                    .transition(.opacity)
                controls()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
            }
        } secondary: {
            ArtPageView(page: page, live: live, popDepth: popDepth, replaysClips: replaysClips, pictureUnavailable: pictureUnavailable)
                .pageCurl(progress: curl)
                .id(page?.id)
                // Page 1 arrives with its words in one crossfade; later pages flip in.
                .transition(page == nil ? AnyTransition.opacity : AnyTransition(PageFlipTransition()))
        }
        .arrangementViewStyle(.split)
        .background(Theme.paper)
        .animation(.easeInOut(duration: 0.45), value: page?.id)
        .ignoresSafeArea()
    }

    @ViewBuilder private var textPage: some View {
        if page == nil, let emptyText {
            TextPageView(text: "", level: level, pageNumber: pageNumber, placeholder: emptyText)
        } else {
            TextPageView(text: page?.text ?? "", level: level, pageNumber: pageNumber, highlight: highlight,
                         question: showsQuestion ? page?.question : nil)
        }
    }
}

extension SpreadView where Controls == EmptyView {
    init(page: PageContent?, pageNumber: Int, level: ReadingLevel, curl: Double, popDepth: Double = 0,
         live: LivePageController? = nil, replaysClips: Bool = false, highlight: NSRange? = nil, pictureUnavailable: Bool = false,
         emptyText: String? = nil) {
        self.init(page: page, pageNumber: pageNumber, level: level, curl: curl, popDepth: popDepth,
                  live: live, replaysClips: replaysClips, highlight: highlight, pictureUnavailable: pictureUnavailable,
                  emptyText: emptyText) { EmptyView() }
    }
}
