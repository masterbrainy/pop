import SwiftUI

/// Chooses the first screen. `-probe <name>` opens a Phase 0 probe directly, for automation.
struct RootView: View {
    var body: some View {
        if let probe = LaunchOptions.probe.flatMap(Probe.init(rawValue:)) {
            probe.destination
        } else {
            ProbeMenuView()
        }
    }
}
