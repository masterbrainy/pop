import OSLog

/// Unified logging. `simctl spawn … log` fails on this Mac (getpwuid_r), so probes
/// also write their results to Documents with `FileLog`.
enum AppLog {
    static let subsystem = "com.masterbrainy.pop"
    static let probe = Logger(subsystem: subsystem, category: "probe")
    static let scene = Logger(subsystem: subsystem, category: "scene")
    static let story = Logger(subsystem: subsystem, category: "story")
}
