import SwiftUI

/// Probe 0.1: shows every hinge update live and logs it, to learn whether the simulator
/// delivers a continuous angle, how often, its range, and whether an update arrives on appear.
struct HingeProbeView: View {
    @State private var rows: [HingeProbeRow] = []
    @State private var latest = "No hinge update yet"
    @State private var start = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hinge probe").font(.title.bold())
            Text(latest).font(.system(.title3, design: .monospaced))
            Text("\(rows.count) updates").foregroundStyle(.secondary)
            List(rows.reversed()) { row in
                Text(row.line).font(.system(.caption, design: .monospaced))
            }
            .listStyle(.plain)
        }
        .padding()
        .onAppear {
            start = Date()
            AppLog.probe.log("HINGE probe appeared")
        }
        .onHingeChange { _, newContext in
            record(newContext)
        }
    }

    private func record(_ context: DeviceHingeContext) {
        let seconds = Date().timeIntervalSince(start)
        let line = HingeProbeRow.describe(context, at: seconds)
        latest = line
        rows.append(HingeProbeRow(id: rows.count, line: line))
        AppLog.probe.log("HINGE \(line, privacy: .public)")
    }
}

struct HingeProbeRow: Identifiable {
    let id: Int
    let line: String

    static func describe(_ context: DeviceHingeContext, at seconds: TimeInterval) -> String {
        guard let hinge = context.hinge else {
            return String(format: "t=%8.3f hinge=nil", seconds)
        }
        return String(
            format: "t=%8.3f status=%@ angle=%6.2f° (%.4f rad)",
            seconds, statusName(hinge.status), hinge.angle.degrees, hinge.angle.radians
        )
    }

    static func statusName(_ status: DeviceHinge.Status) -> String {
        if status == .closed { return "closed" }
        if status == .partiallyOpen { return "partiallyOpen" }
        if status == .fullyOpen { return "fullyOpen" }
        return "other"
    }
}
