import PopKit
import SwiftUI

/// The right page: the page's picture (a still for now; the live animation sits on top from
/// Phase 3). A soft "painting…" placeholder shows until the picture exists (PRD §7 step 3).
struct ArtPageView: View {
    let page: PageContent?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Theme.paperShade
                if let image = StillImageLoader.image(for: page?.stillPath) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    PaintingPlaceholder(isEmpty: page?.text.isEmpty ?? true)
                }
            }
        }
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
