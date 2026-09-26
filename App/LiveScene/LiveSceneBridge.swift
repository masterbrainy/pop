import PopKit
import WebKit

/// Hosts the live-scene page (`web/live-scene`) in a WKWebView and turns its
/// `window.popScene` API into async Swift calls. Events come back on `events`.
/// One bridge drives one Orbis session at a time.
@MainActor
final class LiveSceneBridge: NSObject {
    enum BridgeError: LocalizedError {
        case pageDidNotLoad
        case script(function: String, message: String)

        var errorDescription: String? {
            switch self {
            case .pageDidNotLoad: "The live-scene page didn't load."
            case let .script(function, message): "popScene.\(function) failed: \(message)"
            }
        }

        /// A newer page flow replaced this one (web/live-scene/src/gate.ts `SupersededError`).
        var isSuperseded: Bool {
            if case let .script(_, message) = self { return message.contains("superseded:") }
            return false
        }
    }

    struct ConnectResult: Sendable {
        let sessionId: String?
        let connectMs: Int
    }

    struct PrepareResult: Sendable {
        let width: Int?
        let height: Int?
        let prepareMs: Int
    }

    let webView: WKWebView
    let events: AsyncStream<SceneEvent>
    private let sink: AsyncStream<SceneEvent>.Continuation
    private let schemeHandler: SceneSchemeHandler
    private let clips = ClipAssembler()
    private(set) var pageLoaded = false

    override init() {
        let handler = SceneSchemeHandler()
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.setURLSchemeHandler(handler, forURLScheme: SceneSchemeHandler.scheme)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.isUserInteractionEnabled = false
        #if DEBUG
        webView.isInspectable = true
        #endif
        let (events, sink) = AsyncStream.makeStream(of: SceneEvent.self, bufferingPolicy: .bufferingNewest(1_000))
        self.schemeHandler = handler
        self.webView = webView
        self.events = events
        self.sink = sink
        super.init()
        webView.navigationDelegate = self
        webView.configuration.userContentController.add(WeakScriptMessageHandler(target: self), name: "pop")
        webView.configuration.userContentController.add(WeakScriptMessageHandler(target: self), name: "popClip")
    }

    /// Loads the page and waits for its `loaded` event.
    func load(timeout: Duration = .seconds(45)) async throws {
        if pageLoaded { return }
        webView.load(URLRequest(url: SceneSchemeHandler.pageURL))
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !pageLoaded {
            guard clock.now < deadline else { throw BridgeError.pageDidNotLoad }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    func connect(jwt: String) async throws -> ConnectResult {
        let result = try await call("connect", ["jwt": jwt]) as? [String: Any] ?? [:]
        return ConnectResult(sessionId: result["sessionId"] as? String, connectMs: Self.int(result["connectMs"]) ?? 0)
    }

    /// reset (if needed) → set_image → set_prompt → conditions_ready, as page flow `generation`
    /// (newest wins; an older one throws "superseded: …"). The still is served to the page only while this runs.
    func prepare(still: Data, mimeType: String, prompt: String, seed: Int? = nil, generation: Int? = nil) async throws -> PrepareResult {
        let stillURL = schemeHandler.registerStill(still, mimeType: mimeType)
        defer { schemeHandler.removeStill(at: stillURL) }
        var arguments: [String: Any] = ["imageUrl": stillURL.absoluteString, "prompt": prompt]
        if let seed { arguments["seed"] = seed }
        if let generation { arguments["generation"] = generation }
        let result = try await call("prepare", arguments) as? [String: Any] ?? [:]
        return PrepareResult(width: Self.int(result["width"]), height: Self.int(result["height"]), prepareMs: Self.int(result["prepareMs"]) ?? 0)
    }

    /// Sends `start` for page flow `generation` (default: the newest prepared) and waits for
    /// `generation_started`; returns how long that took in ms.
    func start(generation: Int? = nil) async throws -> Int {
        let arguments: [String: Any] = generation.map { ["generation": $0] } ?? [:]
        let result = try await call("start", arguments) as? [String: Any] ?? [:]
        return Self.int(result["startMs"]) ?? 0
    }

    func setPrompt(_ prompt: String) async throws {
        _ = try await call("setPrompt", ["prompt": prompt])
    }

    func pause() async throws { _ = try await call("pause") }
    func resume() async throws { _ = try await call("resume") }
    func reset() async throws { _ = try await call("reset") }

    /// How the video fills the page: "cover", "contain" or "fill".
    func setFit(_ fit: String) async throws {
        _ = try await call("setFit", ["fit": fit])
    }

    /// Starts recording the video now playing; it stops by itself after `maxSeconds`.
    func startClip(maxSeconds: Int) async throws {
        _ = try await call("startClip", ["maxSeconds": maxSeconds])
    }

    /// Stops recording and returns the clip once all of it is on disk.
    func stopClip() async throws -> ClipAssembler.Clip {
        let result = try await call("stopClip") as? [String: Any] ?? [:]
        guard let clipId = result["clipId"] as? String else { throw ClipAssembler.ClipError.malformed }
        return try await clips.clip(clipId)
    }

    /// Throws away a clip in progress (the page turned before it completed).
    func cancelClip() async {
        _ = try? await call("cancelClip")
    }

    /// The frame now showing as a small JPEG (base64), for the moderation tripwire.
    func sampleFrame(maxSide: Int) async throws -> (base64: String, mimeType: String) {
        let result = try await call("sampleFrame", ["maxSide": maxSide]) as? [String: Any] ?? [:]
        guard let base64 = result["base64"] as? String, let mimeType = result["mimeType"] as? String else {
            throw BridgeError.script(function: "sampleFrame", message: "no frame returned")
        }
        return (base64, mimeType)
    }

    /// Ends the Orbis session (the SDK's disconnect always ends it on the server).
    func disconnect() async throws {
        _ = try await call("disconnect")
    }

    private func call(_ function: String, _ arguments: [String: Any] = [:]) async throws -> Any? {
        do {
            return try await webView.callAsyncJavaScript(
                "return await window.popScene.\(function)(args)",
                arguments: ["args": arguments],
                contentWorld: .page
            )
        } catch {
            throw BridgeError.script(function: function, message: Self.scriptMessage(from: error))
        }
    }

    private func receive(_ event: SceneEvent) {
        if case .loaded = event { pageLoaded = true }
        sink.yield(event)
    }

    private static func scriptMessage(from error: any Error) -> String {
        let info = (error as NSError).userInfo
        return info["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription
    }

    private static func int(_ value: Any?) -> Int? {
        (value as? NSNumber).flatMap { Int(exactly: $0.doubleValue.rounded()) }
    }
}

extension LiveSceneBridge: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "popClip" {
            clips.receive(message.body)
            return
        }
        guard let event = SceneEvent(body: message.body) else {
            AppLog.scene.error("live scene sent an unknown message")
            return
        }
        receive(event)
    }
}

extension LiveSceneBridge: WKNavigationDelegate {
    /// Only the bundled live-scene page (`popscene://app/...`) and `about:blank`
    /// may load in this web view; everything else — a link the scene's own
    /// script tried to open, a redirect, anything else — is cancelled (R-34).
    private func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        let isAllowedScene = url.scheme == SceneSchemeHandler.scheme && url.host == "app"
        let isAboutBlank = url.scheme == "about" && url.path == "blank"
        decisionHandler(isAllowedScene || isAboutBlank ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        receive(.error(code: "navigation", message: error.localizedDescription, recoverable: false))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        receive(.error(code: "navigation", message: error.localizedDescription, recoverable: false))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        pageLoaded = false
        receive(.error(code: "webcontent.terminated", message: "The web content process ended.", recoverable: true))
    }
}

/// WKUserContentController keeps its handlers strongly; this breaks the cycle
/// bridge → web view → content controller → bridge.
@MainActor
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: (any WKScriptMessageHandler)?

    init(target: any WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
