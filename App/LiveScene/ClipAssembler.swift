import Foundation

/// Rebuilds a page clip from the base64 chunks the live-scene page posts on `popClip`
/// (web/live-scene/src/clip.ts) and writes it to `Documents/clips/<clipId>.<ext>`.
@MainActor
final class ClipAssembler {
    struct Clip: Sendable, Equatable {
        let url: URL
        let bytes: Int
        let durationMs: Int
    }

    enum ClipError: LocalizedError {
        case malformed
        case missingChunks(clipId: String)
        case timedOut(clipId: String)

        var errorDescription: String? {
            switch self {
            case .malformed: "The page sent a clip chunk we couldn't read."
            case let .missingChunks(clipId): "Clip \(clipId) arrived with chunks missing."
            case let .timedOut(clipId): "Clip \(clipId) didn't finish arriving."
            }
        }
    }

    private var parts: [String: [Int: Data]] = [:]
    private var finished: [String: Result<Clip, ClipError>] = [:]
    private let directory: URL

    init(directory: URL = URL.documentsDirectory.appending(path: "clips", directoryHint: .isDirectory)) {
        self.directory = directory
    }

    /// Takes one `popClip` message body.
    func receive(_ body: Any) {
        guard let message = body as? [String: Any],
              let clipId = message["clipId"] as? String,
              let seq = (message["seq"] as? NSNumber)?.intValue,
              let base64 = message["base64"] as? String,
              let data = Data(base64Encoded: base64)
        else {
            AppLog.scene.error("clip chunk malformed")
            return
        }
        parts[clipId, default: [:]][seq] = data
        guard (message["last"] as? Bool) == true else { return }
        let mimeType = message["mimeType"] as? String ?? "video/mp4"
        let durationMs = (message["durationMs"] as? NSNumber)?.intValue ?? 0
        finished[clipId] = assemble(clipId: clipId, lastSeq: seq, mimeType: mimeType, durationMs: durationMs)
    }

    /// Waits until clip `clipId` is complete on disk.
    func clip(_ clipId: String, timeout: Duration = .seconds(20)) async throws -> Clip {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if let result = finished.removeValue(forKey: clipId) { return try result.get() }
            try await Task.sleep(for: .milliseconds(50))
        }
        parts[clipId] = nil
        throw ClipError.timedOut(clipId: clipId)
    }

    private func assemble(clipId: String, lastSeq: Int, mimeType: String, durationMs: Int) -> Result<Clip, ClipError> {
        let chunks = parts.removeValue(forKey: clipId) ?? [:]
        guard chunks.count == lastSeq + 1 else { return .failure(.missingChunks(clipId: clipId)) }
        let data = (0...lastSeq).reduce(into: Data()) { whole, seq in whole.append(chunks[seq] ?? Data()) }
        let url = directory.appending(path: "\(clipId).\(mimeType.contains("webm") ? "webm" : "mp4")")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return .success(Clip(url: url, bytes: data.count, durationMs: durationMs))
        } catch {
            AppLog.scene.error("clip write failed: \(error.localizedDescription, privacy: .public)")
            return .failure(.malformed)
        }
    }
}
