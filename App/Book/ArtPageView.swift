import PopKit
import SwiftUI

/// The right page, as layers: the still (drifting slowly as the fallback), a saved book's
/// recorded clip, the live Orbis video on top once its first frame arrives, and the pop-up
/// diorama as the phone folds toward 90° (PRD P3–P6). A soft "Painting…" placeholder shows
/// until the picture exists (PRD §7 step 3).
struct ArtPageView: View {
    let page: PageContent?
    var live: LivePageController? = nil
    var popDepth: Double = 0
    /// Saved books replay their clips; while creating, the live scene runs instead.
    var replaysClips = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Theme.paperShade
                if let image = StillImageLoader.image(for: page?.stillPath) {
                    picture(image, size: proxy.size)
                } else {
                    PaintingPlaceholder(isEmpty: page?.text.isEmpty ?? true)
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
                LiveSceneView(bridge: live.bridge)
                    .opacity(live.isLive ? 1 : 0)
                    .animation(.easeInOut(duration: 0.8), value: live.isLive)
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
        if let layers = page?.layers, let plate = StillImageLoader.image(for: layers.platePath) {
            PopUpView(plate: plate, cutouts: layers.cutouts.compactMap { StillImageLoader.image(for: $0.path) }, depth: popDepth)
        } else {
            PopUpCardView(image: image, depth: popDepth)
        }
    }

    private var showsLiveVideo: Bool {
        (live?.isLive ?? false) || (replaysClips && page?.clipPath != nil)
    }
}

private struct PaintingPlaceholder: View {
    let isEmpty: Bool
    @State private var breathing = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: isEmpty ? "book.pages" : "paintbrush.pointed")
                .font(.system(size: 44))
                .scaleEffect(breathing ? 1.06 : 0.94)
            Text(isEmpty ? "A new page" : "Painting…")
                .font(Theme.storyFont(size: 20))
        }
        .foregroundStyle(Theme.softInk)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { breathing = true }
        }
    }
}
