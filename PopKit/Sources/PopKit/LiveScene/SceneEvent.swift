import Foundation

/// An event the live-scene web page posts to Swift through
/// `window.webkit.messageHandlers.pop` (see `web/live-scene/src/bridge.ts`;
/// keep the two in step).
public enum SceneEvent: Sendable, Equatable {
    case loaded(secureContext: Bool, webRTC: Bool, wasm: Bool)
    case status(String)
    case session(id: String?)
    case track(name: String, kind: String)
    case state(started: Bool?, paused: Bool?, hasImage: Bool?, chunk: Int?)
    case chunk(index: Int?, frames: Int?)
    case model(type: String, json: String)
    case runtime(type: String, json: String)
    /// `generation` is the page flow the frame belongs to (nil from pages that predate it).
    case firstFrame(generation: Int?, sinceStartMs: Double?, width: Int, height: Int)
    case stats(fps: Double?, rttMs: Double?, kbps: Double?)
    case error(code: String, message: String, recoverable: Bool)
    case log(String)

    /// Decodes one `postMessage` body. Returns nil for anything that isn't a known, well-formed event.
    public init?(body: Any) {
        guard let fields = body as? [String: Any], let name = fields["event"] as? String else { return nil }
        let read = FieldReader(fields: fields)
        guard let event = Self.decode(name, read) else { return nil }
        self = event
    }

    /// A one-line description for logs and the debug overlay.
    public var summary: String {
        switch self {
        case let .loaded(secure, webRTC, wasm): "loaded secure=\(secure) webRTC=\(webRTC) wasm=\(wasm)"
        case let .status(status): "status \(status)"
        case let .session(id): "session \(id ?? "none")"
        case let .track(name, kind): "track \(name) (\(kind))"
        case let .state(started, paused, hasImage, chunk):
            "state started=\(Self.text(started)) paused=\(Self.text(paused)) image=\(Self.text(hasImage)) chunk=\(Self.text(chunk))"
        case let .chunk(index, frames): "chunk \(Self.text(index)) · \(Self.text(frames)) frames"
        case let .model(type, json): "model \(type) \(json)"
        case let .runtime(type, json): "runtime \(type) \(json)"
        case let .firstFrame(_, ms, width, height): "first frame after \(Self.text(ms.map { Int($0) })) ms at \(width)×\(height)"
        case let .stats(fps, rtt, kbps):
            "stats fps=\(Self.text(fps.map { Int($0.rounded()) })) rtt=\(Self.text(rtt.map { Int($0) }))ms kbps=\(Self.text(kbps.map { Int($0) }))"
        case let .error(code, message, _): "error \(code): \(message)"
        case let .log(text): "log \(text)"
        }
    }

    private static func decode(_ name: String, _ read: FieldReader) -> SceneEvent? {
        switch name {
        case "loaded":
            guard let secure = read.bool("secureContext"), let webRTC = read.bool("webRTC"), let wasm = read.bool("wasm") else { return nil }
            return .loaded(secureContext: secure, webRTC: webRTC, wasm: wasm)
        case "status": return read.string("status").map(SceneEvent.status)
        case "session": return .session(id: read.string("id"))
        case "track":
            guard let trackName = read.string("name"), let kind = read.string("kind") else { return nil }
            return .track(name: trackName, kind: kind)
        case "state":
            return .state(started: read.bool("started"), paused: read.bool("paused"), hasImage: read.bool("hasImage"), chunk: read.int("chunk"))
        case "chunk": return .chunk(index: read.int("index"), frames: read.int("frames"))
        case "model", "runtime":
            guard let type = read.string("type"), let json = read.string("json") else { return nil }
            return name == "model" ? .model(type: type, json: json) : .runtime(type: type, json: json)
        case "firstFrame":
            guard let width = read.int("width"), let height = read.int("height") else { return nil }
            return .firstFrame(generation: read.int("generation"), sinceStartMs: read.double("sinceStartMs"), width: width, height: height)
        case "stats": return .stats(fps: read.double("fps"), rttMs: read.double("rttMs"), kbps: read.double("kbps"))
        case "error":
            guard let code = read.string("code"), let message = read.string("message") else { return nil }
            return .error(code: code, message: message, recoverable: read.bool("recoverable") ?? false)
        case "log": return read.string("text").map(SceneEvent.log)
        default: return nil
        }
    }

    private static func text<T>(_ value: T?) -> String {
        value.map { "\($0)" } ?? "–"
    }
}

/// Reads typed values out of a WebKit message body, where JavaScript numbers
/// arrive as `NSNumber` and `null` as `NSNull`.
private struct FieldReader {
    let fields: [String: Any]

    func string(_ key: String) -> String? { fields[key] as? String }

    func bool(_ key: String) -> Bool? {
        if let value = fields[key] as? Bool { return value }
        return (fields[key] as? NSNumber)?.boolValue
    }

    func double(_ key: String) -> Double? {
        switch fields[key] {
        case let value as Double: value.isFinite ? value : nil
        case let value as Int: Double(value)
        case let value as NSNumber: value.doubleValue.isFinite ? value.doubleValue : nil
        default: nil
        }
    }

    func int(_ key: String) -> Int? {
        double(key).flatMap { Int(exactly: $0.rounded()) }
    }
}
