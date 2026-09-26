import PopKit
import SwiftUI

/// What the closed phone's outer screen shows: the book's cover with its title line
/// ("Title, a story for Maya", PRD H3). Cover art arrives in Phase 5.
struct CoverView: View {
    let book: Book
    let kid: KidProfile

    var body: some View {
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
                Text(book.title ?? book.bible.title ?? "A new story")
                    .font(Theme.titleFont(size: 34))
                    .multilineTextAlignment(.center)
                Text("a story for \(kid.firstName)")
                    .font(Theme.storyFont(size: 20))
                    .opacity(0.9)
                Spacer()
                Text(book.status == .finished ? "Open to read" : "Open to keep going")
                    .font(.footnote.weight(.semibold))
                    .opacity(0.8)
                    .padding(.bottom, 40)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
        }
        .ignoresSafeArea()
    }
}
