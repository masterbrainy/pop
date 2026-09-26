import Foundation
import WebKit

/// Serves the bundled live-scene page (HTML, JS, wasm) and the current page still
/// to the web view under `popscene://app/…`. A real origin lets the page fetch its
/// own wasm and call Reactor's API, which allows any origin (checked 2026-09-26).
/// Only the three bundled files and registered stills are served; nothing else in
/// the app bundle or on disk is reachable.
@MainActor
final class SceneSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "popscene"
    static let pageURL = URL(string: "popscene://app/live-scene.html")!

    private static let bundledFiles: [String: String] = [
        "live-scene.html": "text/html; charset=utf-8",
        "live-scene.js": "text/javascript; charset=utf-8",
        "reactor_wasm_bg.wasm": "application/wasm",
    ]

    private var stills: [String: Resource] = [:]

    private struct Resource {
        let data: Data
        let mimeType: String
    }

    /// Makes `data` fetchable by the page; returns the URL to pass to `popScene.prepare`.
    func registerStill(_ data: Data, mimeType: String) -> URL {
        let path = "still/\(UUID().uuidString)"
        stills = stills.merging([path: Resource(data: data, mimeType: mimeType)]) { _, new in new }
        return URL(string: "popscene://app/\(path)")!
    }

    func removeStill(at url: URL) {
        stills = stills.filter { $0.key != Self.path(of: url) }
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        if let resource = resource(at: Self.path(of: url)) {
            respond(to: urlSchemeTask, url: url, status: 200, resource: resource)
        } else {
            AppLog.scene.error("popscene: no resource at \(url.path, privacy: .public)")
            respond(to: urlSchemeTask, url: url, status: 404, resource: Resource(data: Data("not found".utf8), mimeType: "text/plain"))
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}

    private func resource(at path: String) -> Resource? {
        if let still = stills[path] { return still }
        guard let mimeType = Self.bundledFiles[path], let fileURL = Self.bundleURL(for: path) else { return nil }
        do {
            return Resource(data: try Data(contentsOf: fileURL), mimeType: mimeType)
        } catch {
            AppLog.scene.error("popscene: could not read \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func respond(to task: any WKURLSchemeTask, url: URL, status: Int, resource: Resource) {
        let headers = [
            "Content-Type": resource.mimeType,
            "Content-Length": String(resource.data.count),
            "Cache-Control": "no-store",
        ]
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else {
            task.didFailWithError(URLError(.cannotParseResponse))
            return
        }
        task.didReceive(response)
        task.didReceive(resource.data)
        task.didFinish()
    }

    /// Xcode copies a synced folder's resources flat into the bundle; fall back to a `Web/` subfolder.
    private static func bundleURL(for name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: nil)
            ?? Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "Web")
    }

    private static func path(of url: URL) -> String {
        String(url.path(percentEncoded: false).drop { $0 == "/" })
    }
}
