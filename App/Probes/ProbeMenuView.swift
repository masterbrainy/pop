import SwiftUI

/// Phase 0 probes, each answering one question about the platform (ROADMAP §5).
enum Probe: String, CaseIterable, Identifiable {
    case hinge
    case spread
    case orbis

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hinge: "0.1 Hinge"
        case .spread: "0.2 Spread"
        case .orbis: "0.3a Orbis"
        }
    }

    @MainActor @ViewBuilder var destination: some View {
        switch self {
        case .hinge: HingeProbeView()
        case .spread: SpreadProbeView()
        case .orbis: OrbisProbeView()
        }
    }
}

struct ProbeMenuView: View {
    var body: some View {
        NavigationStack {
            List(Probe.allCases) { probe in
                NavigationLink(probe.title) { probe.destination }
            }
            .navigationTitle("Pop! probes")
        }
    }
}
