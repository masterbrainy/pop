import PopKit
import SwiftUI

/// The bookshelf: every book as a cover, plus "New book". Finished books open to read (with
/// their recorded clips); drafts open to keep telling. Parent settings sit behind a gate.
struct BookshelfView: View {
    @State private var model = AppModel()
    @State private var openBook: OpenBook?
    @State private var askingBrief = false
    @State private var gate: GateTarget?
    @State private var showsSettings = false
    @State private var sharing: SharedPDF?

    private struct OpenBook: Identifiable {
        let book: Book
        let mode: BookMode
        /// Set only when this book is starting fresh from a brief that drew a hero.
        var heroDrawing: HeroDrawing?
        var id: Book.ID { book.id }
    }

    private enum GateTarget: Identifiable {
        case settings
        case share(Book)
        case delete(Book)
        var id: String {
            switch self {
            case .settings: "settings"
            case let .share(book): "share-\(book.id)"
            case let .delete(book): "delete-\(book.id)"
            }
        }
    }

    private struct SharedPDF: Identifiable {
        let url: URL
        var id: URL { url }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let error = model.loadError {
                    Text(error).font(.footnote).foregroundStyle(Theme.accent).padding(.top, 8)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 24)], spacing: 28) {
                    newBookTile
                    ForEach(model.books) { book in
                        Button { open(book) } label: { BookTile(book: book) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Share as PDF", systemImage: "square.and.arrow.up") { gate = .share(book) }
                                Button("Delete", systemImage: "trash", role: .destructive) { gate = .delete(book) }
                            }
                    }
                }
                .padding(24)
            }
            .background(Theme.paper)
            .navigationTitle(model.kid.firstName.isEmpty ? "Books" : "\(model.kid.firstName)'s books")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { gate = .settings } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Parent settings")
                }
            }
        }
        .task { await model.load() }
        .sheet(isPresented: $askingBrief) {
            BriefSheet(kid: model.kid, onStart: { brief, heroDrawing, firstName in
                askingBrief = false
                model.setFirstName(firstName)
                openBook = OpenBook(book: model.newBook(brief: brief), mode: .creating, heroDrawing: heroDrawing)
            }, onCancel: { askingBrief = false })
        }
        .fullScreenCover(item: $gate) { target in
            ParentGate(onPass: { pass(target) }, onCancel: { gate = nil })
        }
        .sheet(isPresented: $showsSettings) {
            ParentSettingsView(kid: model.kid, settings: model.settings, readAlong: ParentPreferences.readAlong,
                               onSave: { model.update(kid: $0, settings: $1) }, onDone: { showsSettings = false })
        }
        .sheet(item: $sharing) { pdf in
            ShareLink(item: pdf.url) { Label("Share the PDF", systemImage: "square.and.arrow.up") }
                .padding(40)
                .presentationDetents([.height(160)])
        }
        .fullScreenCover(item: $openBook) { open in
            BookView(book: open.book, kid: model.kid, settings: model.settings, mode: open.mode, heroDrawing: open.heroDrawing,
                     onClose: { openBook = nil },
                     onFinish: { book in Task { await model.save(book) } })
        }
    }

    private func open(_ book: Book) {
        openBook = OpenBook(book: book, mode: book.status == .finished ? .reading : .creating)
    }

    private func pass(_ target: GateTarget) {
        gate = nil
        switch target {
        case .settings:
            showsSettings = true
        case let .share(book):
            if let url = try? PDFExporter.export(book, kid: model.kid) { sharing = SharedPDF(url: url) }
        case let .delete(book):
            Task { await model.delete(book) }
        }
    }

    private var newBookTile: some View {
        Button { askingBrief = true } label: {
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
        .accessibilityLabel("Make a new book")
    }
}

private struct BookTile: View {
    let book: Book

    private var pageCount: String { book.pages.count == 1 ? "1 page" : "\(book.pages.count) pages" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The picture fills a fixed tile; a wide page picture is cropped, never widens the tile.
            LinearGradient(colors: [Theme.coverTop, Theme.coverBottom], startPoint: .top, endPoint: .bottom)
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .overlay {
                    if let image = StillImageLoader.image(for: book.coverPath ?? book.pages.first?.stillPath) {
                        Image(uiImage: image).resizable().scaledToFill()
                    }
                }
                .clipShape(.rect(cornerRadius: 22))
            .shadow(color: .black.opacity(0.15), radius: 10, y: 6)
            Text(book.title ?? book.bible.title ?? "A new story")
                .font(Theme.titleFont(size: 17))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
            Text(book.status == .finished ? pageCount : "Still being told · \(pageCount)")
                .font(.caption)
                .foregroundStyle(Theme.softInk)
        }
    }
}
