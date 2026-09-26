import PopKit
import SwiftUI

/// Chooses the first screen: the bookshelf, or for automation `-probe <name>` (a Phase 0
/// probe, or `menu` for the probe list) and `-screen create` (a new book) or `-screen latest` (the newest saved book).
struct RootView: View {
    var body: some View {
        if LaunchOptions.probe == "menu" {
            ProbeMenuView()
        } else if let probe = LaunchOptions.probe.flatMap(Probe.init(rawValue:)) {
            probe.destination
        } else if LaunchOptions.screen == "create" || LaunchOptions.screen == "latest" {
            AutomationBookView(opensLatest: LaunchOptions.screen == "latest")
        } else {
            BookshelfView()
        }
    }
}

/// For end-to-end checks: `-screen create` makes and saves a new book; `-screen latest`
/// opens the newest saved book to read (its clips replay without Reactor).
private struct AutomationBookView: View {
    let opensLatest: Bool
    @State private var model = AppModel()
    @State private var book: Book?
    @State private var hasNoSavedBook = false

    var body: some View {
        Group {
            if hasNoSavedBook {
                ContentUnavailableView("No saved books", systemImage: "books.vertical")
            } else if let book {
                BookView(book: book, kid: model.kid, settings: model.settings, mode: opensLatest ? .reading : .creating,
                         heroDrawing: opensLatest ? nil : LaunchOptions.heroDrawing,
                         onFinish: { finished in Task { await model.save(finished) } })
            } else {
                ProgressView()
            }
        }
        .task {
            await model.load()
            if opensLatest {
                guard let latest = model.books.first else {
                    hasNoSavedBook = true
                    return
                }
                let log = FileLog(name: "replay")
                log.append("opened \(latest.title ?? "?") · pages \(latest.pages.count) · clips on disk \(latest.pages.filter { $0.clipPath.map { FileManager.default.fileExists(atPath: $0) } ?? false }.count)")
                book = latest
            } else {
                book = model.newBook(brief: StoryBrief(interests: model.kid.interests))
            }
        }
    }
}
