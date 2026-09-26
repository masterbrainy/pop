import PopKit
import SwiftUI

/// What the closed phone's outer screen shows: the book's cover with its title line
/// ("Title, a story for Maya", PRD H3). A finished book's painted cover fills the screen with
/// the title over its sky; a draft shows its first picture on the plain cover.
struct CoverView: View {
    let book: Book
    let kid: KidProfile

    var body: some View {
        if let art = StillImageLoader.image(for: book.coverPath), book.coverPath != book.pages.first?.stillPath {
            paintedCover(art)
        } else {
            plainCover
        }
    }

    private func paintedCover(_ art: UIImage) -> some View {
        ZStack {
            Image(uiImage: art)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
            LinearGradient(colors: [.black.opacity(0.45), .clear, .clear, .black.opacity(0.35)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 10) {
                titleLines
                    .padding(.top, 70)
                Spacer()
                openHint
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
            .padding(.horizontal, 28)
        }
    }

    private var plainCover: some View {
        ZStack {
            LinearGradient(colors: [Theme.coverTop, Theme.coverBottom], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 18) {
                Spacer()
                if let image = StillImageLoader.image(for: book.coverPath ?? book.pages.first?.stillPath) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 280, height: 280)
                        .clipShape(.rect(cornerRadius: 28))
                        .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
                }
                titleLines
                Spacer()
                openHint
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
        }
        .ignoresSafeArea()
    }

    private var titleLines: some View {
        VStack(spacing: 8) {
            Text(book.title ?? book.bible.title ?? "A new story")
                .font(Theme.titleFont(size: 34))
                .multilineTextAlignment(.center)
            Text("a story for \(kid.firstName)")
                .font(Theme.storyFont(size: 20))
                .opacity(0.9)
        }
    }

    private var openHint: some View {
        Text(book.status == .finished ? "Open to read" : "Open to keep going")
            .font(.footnote.weight(.semibold))
            .opacity(0.85)
            .padding(.bottom, 40)
    }
}
