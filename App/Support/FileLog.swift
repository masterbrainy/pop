import Foundation

/// Appends timestamped lines to `Documents/<name>.log`, so a probe's results can be
/// read from the Mac through `xcrun simctl get_app_container … data`.
struct FileLog: Sendable {
    let url: URL
    private let startedAt = Date()

    /// Starts a fresh log, replacing any earlier file with the same name.
    init(name: String) {
        url = URL.documentsDirectory.appending(path: "\(name).log")
        do {
            try Data().write(to: url)
        } catch {
            AppLog.probe.error("FileLog: could not create \(name, privacy: .public).log: \(error.localizedDescription, privacy: .public)")
        }
    }

    func append(_ line: String) {
        let stamped = String(format: "%8.3f ", Date().timeIntervalSince(startedAt)) + line + "\n"
        do {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(stamped.utf8))
        } catch {
            AppLog.probe.error("FileLog: append failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
