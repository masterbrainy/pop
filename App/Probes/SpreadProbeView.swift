import SwiftUI

/// Probe 0.2: the two-pane spread with reserved regions drawn on top, to measure
/// each page's size and see where the fold (division) and camera (occlusion) fall.
struct SpreadProbeView: View {
    var body: some View {
        ArrangementView {
            PaneProbe(label: "primary · text page", tint: .orange)
        } secondary: {
            PaneProbe(label: "secondary · art page", tint: .teal)
        }
        .arrangementViewStyle(.split)
        .ignoresSafeArea()
    }
}

private struct PaneProbe: View {
    let label: String
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let division = proxy.reservedRegions(kind: .division, options: [.includeInactive])
            let occlusion = proxy.reservedRegions(kind: .occlusion, options: [.includeInactive])
            ZStack(alignment: .topLeading) {
                tint.opacity(0.2)
                ForEach(division) { region in RegionOverlay(region: region, color: .red) }
                ForEach(occlusion) { region in RegionOverlay(region: region, color: .purple) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(label).bold()
                    Text("size \(Int(proxy.size.width))×\(Int(proxy.size.height)) pt")
                    Text("division \(Self.describe(division))")
                    Text("occlusion \(Self.describe(occlusion))")
                }
                .font(.system(.caption, design: .monospaced))
                .padding(12)
            }
            .onAppear {
                AppLog.probe.log("SPREAD \(label, privacy: .public) size=\(proxy.size.width)x\(proxy.size.height) division=\(Self.describe(division), privacy: .public) occlusion=\(Self.describe(occlusion), privacy: .public)")
            }
        }
    }

    static func describe(_ regions: [ReservedRegion]) -> String {
        guard !regions.isEmpty else { return "none" }
        return regions.map { region in
            let f = region.frame
            return "[\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))×\(Int(f.height)) active=\(region.isActive)]"
        }.joined(separator: " ")
    }
}

private struct RegionOverlay: View {
    let region: ReservedRegion
    let color: Color

    var body: some View {
        Rectangle()
            .fill(color.opacity(region.isActive ? 0.45 : 0.15))
            .overlay(Rectangle().stroke(color, lineWidth: 2))
            .frame(width: region.frame.width, height: region.frame.height)
            .position(x: region.frame.midX, y: region.frame.midY)
    }
}
