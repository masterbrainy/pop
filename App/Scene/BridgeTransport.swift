import Foundation
import PopKit

/// `SceneTransport` over the web bridge, for `SessionController`.
struct BridgeTransport: SceneTransport {
    let bridge: LiveSceneBridge

    func connect(jwt: String) async throws -> String {
        let result = try await bridge.connect(jwt: jwt)
        return result.sessionId ?? ""
    }

    /// Sends Orbis a ~832×468 16:9 JPEG rather than the stored 1536×1024 PNG (about a tenth of the
    /// bytes, so a shorter upload in every prepare). Runs on the session's actor, off the main thread.
    /// A flow `LivePageController` marked hidden is prepared with `reveal: false` by the bridge.
    func prepare(still: Data, prompt: String, generation: Int) async throws {
        let upload = OrbisStill.jpeg(from: still) ?? still
        let mime = upload.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? "image/png" : "image/jpeg"
        try await superseding {
            _ = try await bridge.prepare(still: upload, mimeType: mime, prompt: prompt, generation: generation)
        }
    }

    func start(generation: Int) async throws {
        try await superseding {
            _ = try await bridge.start(generation: generation)
        }
    }

    func disconnect() async {
        try? await bridge.disconnect()
    }

    /// The page's "superseded: …" rejection becomes `SceneTransportError.superseded`.
    private func superseding(_ body: () async throws -> Void) async throws {
        do {
            try await body()
        } catch let error as LiveSceneBridge.BridgeError where error.isSuperseded {
            throw SceneTransportError.superseded
        }
    }
}
