import PopKit
import SwiftUI

/// Chooses the first screen: the bookshelf, or for automation `-probe <name>` (a Phase 0
/// probe, or `menu` for the probe list) and `-screen book` (the sample book) or `-screen create` (a new book).
struct RootView: View {
    var body: some View {
        if LaunchOptions.probe == "menu" {
            ProbeMenuView()
        } else if let probe = LaunchOptions.probe.flatMap(Probe.init(rawValue:)) {
            probe.destination
        } else if LaunchOptions.screen == "book" {
            BookView(book: SampleBooks.fox, kid: SampleBooks.kid, mode: .reading)
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

    var body: some View {
        Group {
            if let book {
                BookView(book: book, kid: model.kid, settings: model.settings, mode: opensLatest ? .reading : .creating,
                         onFinish: { finished in Task { await model.save(finished) } })
            } else {
                ProgressView()
            }
        }
        .task {
            await model.load()
            if opensLatest {
                let latest = model.books.first { $0.id != SampleBooks.fox.id } ?? SampleBooks.fox
                let log = FileLog(name: "replay")
                log.append("opened \(latest.title ?? "?") · pages \(latest.pages.count) · clips on disk \(latest.pages.filter { $0.clipPath.map { FileManager.default.fileExists(atPath: $0) } ?? false }.count)")
                book = latest
            } else {
                book = model.newBook(brief: StoryBrief(interests: model.kid.interests))
            }
        }
    }
}
