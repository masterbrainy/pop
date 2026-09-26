import PopKit
import SwiftUI

/// Chooses the first screen: the bookshelf, or for automation `-probe <name>` (a Phase 0
/// probe, or `menu` for the probe list) and `-screen book` (the sample book).
struct RootView: View {
    var body: some View {
        if LaunchOptions.probe == "menu" {
            ProbeMenuView()
        } else if let probe = LaunchOptions.probe.flatMap(Probe.init(rawValue:)) {
            probe.destination
        } else if LaunchOptions.screen == "book" {
            BookView(book: SampleBooks.fox, kid: SampleBooks.kid, mode: .reading)
        } else {
            BookshelfView()
        }
    }
}
