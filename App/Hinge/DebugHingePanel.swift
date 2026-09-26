import PopKit
import SwiftUI

/// A small floating panel that drives the hinge by slider or scripted moves, because the
/// simulator's hinge only moves by hand in DeviceHub. Shown with `-debugHinge YES`, or
/// toggled by a triple tap on the book.
struct DebugHingePanel: View {
    let hinge: HingeModel
    @State private var angle: Double = 180

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Hinge \(Int(angle.rounded()))°").monospacedDigit().bold()
                Spacer()
                Text(phaseText).monospacedDigit()
            }
            Slider(value: $angle, in: 0...180, step: 1)
                .onChange(of: angle) { _, degrees in
                    if !hinge.overridden { hinge.setOverride(true) }
                    hinge.ingest(posture: HingeModel.posture(for: degrees), degrees: degrees, from: .debug)
                }
            HStack(spacing: 8) {
                ForEach(HingeScript.Move.allCases, id: \.self) { move in
                    Button(move.rawValue.capitalized) { hinge.play([move]) }
                }
                Spacer()
                Toggle("Debug", isOn: Binding(get: { hinge.overridden }, set: { hinge.setOverride($0) }))
                    .toggleStyle(.button)
            }
            .buttonStyle(.bordered)
        }
        .font(.caption)
        .padding(10)
        .frame(maxWidth: 420)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
    }

    private var phaseText: String {
        let state = hinge.state
        return String(format: "curl %.2f · pop %.2f · %@", state.curl, state.popDepth, String(describing: state.phase))
    }
}
