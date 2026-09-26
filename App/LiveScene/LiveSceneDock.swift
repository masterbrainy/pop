import SwiftUI
import WebKit

/// Keeps the live-scene web view in the window for the whole book, so hidden work (the page
/// behind being pre-animated and recorded) never stops. It parks in a permanent host behind
/// the book (`LiveSceneParking`) and moves into the art page on screen (`LiveSceneSlot`)
/// while that page is shown. Moving between two views in the same window never takes it out
/// of the window, which is what would pause WebKit's video and the clip recording (a page
/// turn used to tear the old art page down, and the closed cover dropped it altogether).
@MainActor
final class LiveSceneDock {
    let webView: WKWebView
    private weak var parking: UIView?
    /// The newest art page's slot. Only it may hold the web view, so an art page still
    /// flipping away (and still getting updates) can't take it back from the new one.
    private weak var currentSlot: UIView?

    init(webView: WKWebView) {
        self.webView = webView
    }

    /// The permanent host: the web view waits here when no art page holds it.
    func park(in host: UIView) {
        parking = host
        if webView.superview == nil { attach(to: host) }
    }

    /// The book is going away: let go of the permanent host.
    func unpark(_ host: UIView) {
        if parking === host { parking = nil }
        if webView.superview === host { webView.removeFromSuperview() }
    }

    /// A new art page came on screen: it takes the web view (the newest one wins).
    func adopt(_ slot: UIView) {
        currentSlot = slot
        claim(slot)
    }

    /// The newest art page keeps (or takes back) the web view; an older one never does. A slot
    /// not yet in the window waits (its `didMoveToWindow` claims again), so the web view never
    /// leaves the window on its way to the new page.
    func claim(_ slot: UIView) {
        guard currentSlot === slot, webView.superview !== slot, slot.window != nil else { return }
        attach(to: slot)
    }

    /// An art page is going away: the web view goes back to the permanent host, if it's still here.
    func release(_ slot: UIView) {
        if currentSlot === slot { currentSlot = nil }
        guard webView.superview === slot else { return }
        if let parking {
            attach(to: parking)
        } else {
            webView.removeFromSuperview()
        }
    }

    private func attach(to host: UIView) {
        host.addSubview(webView)
        webView.frame = host.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }
}

/// The permanent host behind the book (`BookView`), covered by the pages.
struct LiveSceneParking: UIViewRepresentable {
    let dock: LiveSceneDock

    func makeUIView(context: Context) -> DockHostView {
        let view = DockHostView(dock: dock)
        dock.park(in: view)
        return view
    }

    func updateUIView(_ view: DockHostView, context: Context) {}

    static func dismantleUIView(_ view: DockHostView, coordinator: ()) {
        view.dock?.unpark(view)
    }
}

/// The art page's place for the live video (`ArtPageView`): it holds the web view while it's
/// on screen and gives it back to the parking host when it goes.
struct LiveSceneSlot: UIViewRepresentable {
    let dock: LiveSceneDock

    func makeUIView(context: Context) -> DockHostView {
        let view = DockHostView(dock: dock)
        dock.adopt(view)
        return view
    }

    func updateUIView(_ view: DockHostView, context: Context) {
        dock.claim(view)
    }

    static func dismantleUIView(_ view: DockHostView, coordinator: ()) {
        view.dock?.release(view)
    }
}

/// A plain host view that remembers its dock, for `dismantleUIView`.
final class DockHostView: UIView {
    weak var dock: LiveSceneDock?

    init(dock: LiveSceneDock) {
        self.dock = dock
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// An art page's slot takes the web view only once it's in the window.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { dock?.claim(self) }
    }
}
