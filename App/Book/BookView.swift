import PopKit
import SwiftUI

/// A book on the Duo: the spread while open, the cover while closed. Folding turns and
/// pops pages through `HingeModel`; a triple tap shows the debug hinge panel.
struct BookView: View {
    let kid: KidProfile
    var onClose: () -> Void = {}

    @State private var hinge = HingeModel()
    @State private var reader: BookReader
    @State private var showsDebugPanel = LaunchOptions.debugHinge

    init(book: Book, kid: KidProfile, mode: BookMode, onClose: @escaping () -> Void = {}) {
        self.kid = kid
        self.onClose = onClose
        _reader = State(initialValue: BookReader(book: book, mode: mode))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            content
            if showsDebugPanel {
                DebugHingePanel(hinge: hinge)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
            }
        }
        .overlay(alignment: .topLeading) { closeButton }
        .readsHinge(into: hinge)
        .onTapGesture(count: 3) { showsDebugPanel.toggle() }
        .task {
            hinge.onEvent = { [reader] event in reader.handle(event) }
            hinge.start(script: LaunchOptions.hingeScript)
        }
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden()
    }

    @ViewBuilder private var content: some View {
        if hinge.state.phase == .closed {
            CoverView(book: reader.book, kid: kid)
        } else {
            SpreadView(page: reader.currentPage, pageNumber: reader.pageNumber, level: kid.readingLevel, curl: hinge.state.curl)
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.headline)
                .padding(12)
                .background(.ultraThinMaterial, in: .circle)
        }
        .foregroundStyle(Theme.ink)
        .padding(20)
        .accessibilityLabel("Back to the bookshelf")
    }
}
