import PopKit
import SwiftUI

/// The bookshelf: every book as a cover, plus "New book".
struct BookshelfView: View {
    @State private var model = AppModel()
    @State private var openBook: OpenBook?

    private struct OpenBook: Identifiable {
        let book: Book
        let mode: BookMode
        var id: Book.ID { book.id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 24)], spacing: 28) {
                    newBookTile
                    ForEach(model.books) { book in
                        Button { openBook = OpenBook(book: book, mode: book.pages.isEmpty ? .creating : .reading) } label: {
                            BookTile(book: book)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(24)
            }
            .background(Theme.paper)
            .navigationTitle("\(model.kid.firstName)'s books")
        }
        .fullScreenCover(item: $openBook) { open in
            BookView(book: open.book, kid: model.kid, mode: open.mode) { openBook = nil }
        }
    }

    private var newBookTile: some View {
        Button { openBook = OpenBook(book: model.newBook(), mode: .creating) } label: {
            VStack(spacing: 12) {
                Image(systemName: "plus").font(.system(size: 40, weight: .semibold))
                Text("New book").font(Theme.titleFont(size: 20))
            }
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity, minHeight: 240)
            .background(Theme.paperShade.opacity(0.6), in: .rect(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Theme.accent.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [8, 6])))
        }
        .buttonStyle(.plain)
    }
}

private struct BookTile: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                LinearGradient(colors: [Theme.coverTop, Theme.coverBottom], startPoint: .top, endPoint: .bottom)
                if let image = StillImageLoader.image(for: book.coverPath ?? book.pages.first?.stillPath) {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .frame(height: 200)
            .clipShape(.rect(cornerRadius: 22))
            .shadow(color: .black.opacity(0.15), radius: 10, y: 6)
            Text(book.title ?? book.bible.title ?? "A new story")
                .font(Theme.titleFont(size: 17))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
            Text("\(book.pages.count) pages")
                .font(.caption)
                .foregroundStyle(Theme.softInk)
        }
    }
}
