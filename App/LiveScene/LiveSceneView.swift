import SwiftUI
import WebKit

/// Shows a `LiveSceneBridge`'s web view. The page is transparent until its first
/// video frame, so whatever sits behind this view (the page still) shows until then.
struct LiveSceneView: UIViewRepresentable {
    let bridge: LiveSceneBridge

    func makeUIView(context: Context) -> WKWebView {
        bridge.webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
