import SwiftUI

/// The pop-up diorama (PRD P6, ROADMAP Phase 4): the page's background plate tilts back like
/// a stage while each keyed character cutout stands up out of the page. `depth` (0 flat …
/// 1 fully popped) follows the hinge angle through `PostureState.popDepth`.
struct PopUpView: View {
    let plate: UIImage
    let cutouts: [UIImage]
    let depth: Double

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .bottom) {
                Image(uiImage: plate)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .brightness(-0.08 * depth)
                    .rotation3DEffect(.degrees(28 * depth), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.5)

                ForEach(Array(cutouts.enumerated()), id: \.offset) { index, cutout in
                    StandingCutout(image: cutout, depth: stagger(depth, index: index), height: size.height * 0.62)
                        .offset(x: slot(index, of: cutouts.count, width: size.width))
                        .padding(.bottom, size.height * 0.06)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.8), value: depth)
        .accessibilityLabel("The page pops up")
    }

    /// Later cutouts rise a little after earlier ones, so the scene unfolds rather than snaps.
    private func stagger(_ depth: Double, index: Int) -> Double {
        let delay = min(0.3, Double(index) * 0.12)
        return max(0, min(1, (depth - delay) / (1 - delay)))
    }

    private func slot(_ index: Int, of count: Int, width: Double) -> Double {
        guard count > 1 else { return 0 }
        let spread = width * 0.5
        return -spread / 2 + spread * Double(index) / Double(count - 1)
    }
}

/// One character, hinged at its feet: it lies flat on the page at depth 0 and stands at 1.
private struct StandingCutout: View {
    let image: UIImage
    let depth: Double
    let height: Double

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .shadow(color: .black.opacity(0.35 * depth), radius: 10 * depth, x: 0, y: 8 * depth)
            .rotation3DEffect(.degrees(80 * (1 - depth)), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.6)
            .scaleEffect(0.85 + 0.15 * depth, anchor: .bottom)
            .opacity(0.25 + 0.75 * depth)
    }
}

/// Without generated layers (sample books, or layers still being made), the whole still
/// lifts off the page as one card, so the gesture always does something.
struct PopUpCardView: View {
    let image: UIImage
    let depth: Double

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .clipShape(.rect(cornerRadius: 12 * depth))
            .shadow(color: .black.opacity(0.4 * depth), radius: 18 * depth, y: 12 * depth)
            .scaleEffect(1 - 0.12 * depth)
            .rotation3DEffect(.degrees(-24 * depth), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.5)
            .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.8), value: depth)
    }
}
