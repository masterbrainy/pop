import Foundation
import Testing
@testable import PopKit

struct SceneEventTests {
    @Test func decodesLoadedWithCapabilities() {
        let event = SceneEvent(body: ["event": "loaded", "secureContext": true, "webRTC": true, "wasm": false])
        #expect(event == .loaded(secureContext: true, webRTC: true, wasm: false))
    }

    @Test func decodesStatusAndSession() {
        #expect(SceneEvent(body: ["event": "status", "status": "ready"]) == .status("ready"))
        #expect(SceneEvent(body: ["event": "session", "id": "s-1"]) == .session(id: "s-1"))
        #expect(SceneEvent(body: ["event": "session", "id": NSNull()]) == .session(id: nil))
    }

    @Test func decodesChunkWithNumbersFromJavaScript() {
        // WebKit hands JavaScript numbers over as NSNumber doubles.
        let body: [String: Any] = ["event": "chunk", "index": NSNumber(value: 12.0), "frames": NSNumber(value: 33)]
        #expect(SceneEvent(body: body) == .chunk(index: 12, frames: 33))
        #expect(SceneEvent(body: ["event": "chunk", "index": NSNull(), "frames": NSNull()]) == .chunk(index: nil, frames: nil))
    }

    @Test func decodesStateWithMissingFields() {
        let body: [String: Any] = ["event": "state", "started": true, "paused": NSNull(), "hasImage": false, "chunk": 4]
        #expect(SceneEvent(body: body) == .state(started: true, paused: nil, hasImage: false, chunk: 4))
    }

    @Test func decodesFirstFrameAndStats() {
        let frame: [String: Any] = ["event": "firstFrame", "sinceStartMs": 2150, "width": 832, "height": 480]
        #expect(SceneEvent(body: frame) == .firstFrame(sinceStartMs: 2150, width: 832, height: 480))
        let stats: [String: Any] = ["event": "stats", "fps": 17.8, "rttMs": NSNull(), "kbps": 2400]
        #expect(SceneEvent(body: stats) == .stats(fps: 17.8, rttMs: nil, kbps: 2400))
    }

    @Test func decodesModelRuntimeTrackErrorAndLog() {
        #expect(SceneEvent(body: ["event": "model", "type": "conditions_ready", "json": "{}"]) == .model(type: "conditions_ready", json: "{}"))
        #expect(SceneEvent(body: ["event": "runtime", "type": "moderation", "json": "{}"]) == .runtime(type: "moderation", json: "{}"))
        #expect(SceneEvent(body: ["event": "track", "name": "main_video", "kind": "video"]) == .track(name: "main_video", kind: "video"))
        let error: [String: Any] = ["event": "error", "code": "TRANSPORT_ERROR", "message": "ice failed", "recoverable": true]
        #expect(SceneEvent(body: error) == .error(code: "TRANSPORT_ERROR", message: "ice failed", recoverable: true))
        #expect(SceneEvent(body: ["event": "log", "text": "hello"]) == .log("hello"))
    }

    @Test func rejectsUnknownOrMalformedBodies() {
        #expect(SceneEvent(body: "not a dictionary") == nil)
        #expect(SceneEvent(body: ["event": "teleport"]) == nil)
        #expect(SceneEvent(body: ["status": "ready"]) == nil)
        #expect(SceneEvent(body: ["event": "status"]) == nil)
        #expect(SceneEvent(body: ["event": "firstFrame", "width": "wide", "height": 1]) == nil)
    }

    @Test func summaryIsShortAndReadable() {
        #expect(SceneEvent.chunk(index: 3, frames: 33).summary == "chunk 3 · 33 frames")
        #expect(SceneEvent.status("ready").summary == "status ready")
        #expect(SceneEvent.error(code: "X", message: "boom", recoverable: false).summary == "error X: boom")
    }
}
