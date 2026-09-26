import Foundation
import PopKit

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

    /// `-screen book` opens the sample book directly (for automated checks).
    static var screen: String? { UserDefaults.standard.string(forKey: "screen") }

    /// `-logHinge YES` logs hinge readings and posture events to Documents/hinge.log.
    static var logHinge: Bool { UserDefaults.standard.bool(forKey: "logHinge") }

    /// `-debugHinge YES` hands the hinge to the debug panel from launch.
    static var debugHinge: Bool { UserDefaults.standard.bool(forKey: "debugHinge") }

    /// `-hingeScript open,turn,pop` plays scripted hinge moves at launch.
    static var hingeScript: [HingeScript.Move] {
        HingeScript.parse(UserDefaults.standard.string(forKey: "hingeScript") ?? "")
    }

    /// `-screen create -storyTurns "a fox finds a leaf|You continue|fold"` makes a new book and
    /// plays these turns, one after each page settles: text is typed input, "You continue"
    /// taps continue, and "fold" turns to the next page (for end-to-end checks).
    static var storyTurns: [String] {
        (UserDefaults.standard.string(forKey: "storyTurns") ?? "")
            .split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// `-heroDrawing drawing.png -heroName "a red ball with a smile"` starts `-screen create` with
    /// a kid's drawing (a PNG in the app's Documents) as the hero.
    static var heroDrawing: HeroDrawing? {
        guard let name = UserDefaults.standard.string(forKey: "heroDrawing"),
              let data = try? Data(contentsOf: URL.documentsDirectory.appending(path: name)) else { return nil }
        return HeroDrawing(imageData: data, description: UserDefaults.standard.string(forKey: "heroName") ?? "the hero")
    }

    /// `-hingeAngle 95` sweeps the debug hinge from flat to this angle at launch and holds it
    /// (for screenshots of the curl and pop-up).
    static var hingeAngle: Double? {
        UserDefaults.standard.object(forKey: "hingeAngle") == nil ? nil : UserDefaults.standard.double(forKey: "hingeAngle")
    }
}
