import PopKit
import SwiftUI

/// The right page, as layers: the still (drifting slowly as the fallback), the page's baked
/// loop whenever it has one (saved books, and while creating once the loop is ready), the
/// live Orbis video on top while the page is live, and the pop-up diorama as the phone folds
/// toward 90° (PRD P3–P6). While creating, a page is shown only once its picture is finished
/// ("no page until painted"), so before page 1 the right page is a start card; a page whose
/// picture can't come shows the imagine card.
struct ArtPageView: View {
    let page: PageContent?
    var live: LivePageController? = nil
    var popDepth: Double = 0
    /// Moderation turned this page's picture away (IMP-10): no picture is coming.
    var pictureUnavailable = false
    /// The live video hands over to the page's loop with this crossfade.
    static let handOverDuration = 0.4

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
            StillPanView(image: image, isMoving: !showsMotion)
            // A page held by a flagged frame never plays its loop, even before the loop is dropped.
            if let clip = StillImageLoader.url(for: page?.clipPath), !isHeld {
                // Under the live video while it hands over; it says when it can show a frame.
                ClipPlayerView(url: clip, onReady: { [live, key = page?.key] in
                    if let key { live?.clipBecameReady(key) }
                })
                .transition(.opacity)
            }
            if let live {
                // In over the still's settle (same duration); out to the page's loop with a short
                // crossfade; out at once otherwise, so a page's video never lingers over the next page.
                let showsLive = live.isShowingLive(page)
                LiveSceneSlot(dock: live.dock)
                    .opacity(showsLive ? 1 : 0)
                    .animation(liveAnimation(showsLive), value: showsLive)
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

    private var isHeld: Bool {
        guard let live, let page else { return false }
        return live.isHeld(page)
    }

    private var showsMotion: Bool {
        (live?.isShowingLive(page) ?? false) || (page?.clipPath != nil && !isHeld)
    }

    private func liveAnimation(_ showsLive: Bool) -> Animation? {
        if showsLive { return .easeInOut(duration: StillPanMotion.settleDuration) }
        return page?.clipPath != nil ? .easeInOut(duration: Self.handOverDuration) : nil
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
