import PopKit
import SwiftUI

/// The demo operator's view of the living page (ROADMAP Phase 3 and §9): session status,
/// Reactor credits used, frame checks, the p50/p90 stage latencies, and KILL, which ends the
/// Orbis session so the book carries on with still pictures. Shown with the hinge panel
/// (triple tap on the book).
struct SceneDebugOverlay: View {
    let live: LivePageController
    let latency: LatencyTable?
    @State private var killing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(statusText).bold()
                Spacer()
                Button(role: .destructive) {
                    killing = true
                    Task {
                        await live.kill()
                        killing = false
                    }
                } label: {
                    Text(killing ? "Killing…" : "KILL").bold()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(killing || live.status == .off)
            }
            Text(String(format: "credits %.1f · frames checked %d · flagged %d",
                        live.credits, live.framesChecked, live.framesFlagged))
            Text(latencyText)
        }
        .font(.caption.monospacedDigit())
        .padding(10)
        .frame(maxWidth: 420)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
    }

    private var statusText: String {
        switch live.status {
        case .off: "Orbis off"
        case .warming: "Orbis warming"
        case let .preparing(page): "Preparing page \(page + 1)"
        case let .live(page): "Live · page \(page + 1)"
        case let .held(page): "Held on still · page \(page + 1)"
        case let .fallback(message): "Fallback · \(message)"
        }
    }

    private var latencyText: String {
        guard let latency else { return "latency: no turns yet" }
        return "p50/p90 s · turn \(Self.format(latency.storyTurn)) · art \(Self.format(latency.art)) · motion \(Self.format(latency.motionPrompt))"
    }

    private static func format(_ stats: LatencyStats?) -> String {
        guard let stats else { return "–" }
        return String(format: "%.1f/%.1f", stats.p50, stats.p90)
    }
}
