import Foundation

/// Launch arguments used for automation, for example `xcrun simctl launch booted com.masterbrainy.pop -probe hinge`.
/// Arguments of the form `-key value` land in UserDefaults' argument domain.
enum LaunchOptions {
    static var probe: String? { UserDefaults.standard.string(forKey: "probe") }

    /// `-autorun YES` makes a probe run its measurement without a tap.
    static var autorun: Bool { UserDefaults.standard.bool(forKey: "autorun") }

    /// `-probeSeconds N` caps how long a paid probe keeps generating after its first frame.
    static var probeSeconds: Int {
        let value = UserDefaults.standard.integer(forKey: "probeSeconds")
        return value > 0 ? value : 30
    }
}
