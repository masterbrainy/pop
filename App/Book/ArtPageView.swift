import PopKit
import SwiftUI

/// The right page, as layers: the still (drifting slowly as the fallback), a saved book's
/// recorded clip, the live Orbis video on top once its first frame arrives, and the pop-up
/// diorama as the phone folds toward 90° (PRD P3–P6). While creating, a page is shown only
/// once its picture is finished ("no page until painted"), so before page 1 the right page
/// is a start card; a page whose picture can't come shows the imagine card.
struct ArtPageView: View {
    let page: PageContent?
    var live: LivePageController? = nil
    var popDepth: Double = 0
    /// Saved books replay their clips; while creating, the live scene runs instead.
    var replaysClips = false
    /// Moderation turned this page's picture away (IMP-10): no picture is coming.
    var pictureUnavailable = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Theme.paperShade
                if let image = StillImageLoader.frameImage(for: page?.stillPath) {
                    picture(image, size: proxy.size)
                } else if showsImagineCard {
                    ImagineCard()
                } else {
                    WaitingCard()
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }

    @ViewBuilder
    private func picture(_ image: UIImage, size: CGSize) -> some View {
        let popped = popDepth > 0.02
        ZStack {
            StillPanView(image: image, isMoving: !showsLiveVideo)
            if replaysClips, let clip = StillImageLoader.url(for: page?.clipPath) {
                ClipPlayerView(url: clip)
                    .transition(.opacity)
            }
            if let live {
                // The one crossfade: in over the still's settle (same duration), out at once so
                // a page's video never lingers over the next page's still.
                let showsLive = live.isShowingLive(page)
                LiveSceneView(bridge: live.bridge)
                    .opacity(showsLive ? 1 : 0)
                    .animation(showsLive ? .easeInOut(duration: StillPanMotion.settleDuration) : nil, value: showsLive)
                    .allowsHitTesting(false)
            }
        }
        .opacity(popped ? 1 - popDepth * 0.85 : 1)
        .overlay {
            if popped { popUp(image) }
        }
    }

    @ViewBuilder
    private func popUp(_ image: UIImage) -> some View {
        if let layers = page?.layers, let plate = StillImageLoader.frameImage(for: layers.platePath) {
            PopUpView(plate: plate, cutouts: layers.cutouts.compactMap { StillImageLoader.image(for: $0.path) }, depth: popDepth)
        } else {
            PopUpCardView(image: image, depth: popDepth)
        }
    }

    private var showsLiveVideo: Bool {
        (live?.isShowingLive(page) ?? false) || (replaysClips && page?.clipPath != nil)
    }

    /// A page with words but no picture that will never arrive: moderation turned it away, it
    /// failed or ran past its deadline, or it's a saved book being read (nothing is painting then).
    private var showsImagineCard: Bool {
        guard let page, !page.text.isEmpty else { return false }
        return pictureUnavailable || live == nil
    }
}

private struct ImagineCard: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
            Text("Picture this page in your mind!")
                .font(Theme.storyFont(size: 20))
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .foregroundStyle(Theme.softInk)
    }
}

/// The right page with no page to show yet: the start of a new book (never "Painting…": a
/// page shows only with its picture).
private struct WaitingCard: View {
    @State private var breathing = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.pages")
                .font(.system(size: 44))
                .scaleEffect(breathing ? 1.06 : 0.94)
            Text("A new page")
                .font(Theme.storyFont(size: 20))
        }
        .foregroundStyle(Theme.softInk)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { breathing = true }
        }
    }
}
