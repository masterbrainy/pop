import SwiftUI

/// Page curl v1 (ROADMAP Phase 1): the art page lifts around the spine as the phone folds,
/// with shading that deepens as it lifts. Driven by `PostureState.curl` (0…1); hinge updates
/// are sparse, so the value is animated between samples.
struct PageCurl: ViewModifier {
    /// How far the page is lifted toward the turn point.
    let progress: Double
    /// The largest lift, reached at the turn point; the turn itself completes the flip.
    static let maxLiftDegrees = 70.0

    func body(content: Content) -> some View {
        content
            .overlay {
                LinearGradient(
                    colors: [.black.opacity(0.28 * progress), .black.opacity(0.06 * progress)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .allowsHitTesting(false)
            }
            .rotation3DEffect(
                .degrees(-progress * Self.maxLiftDegrees),
                axis: (x: 0, y: 1, z: 0),
                anchor: .leading,
                perspective: 0.55
            )
            .shadow(color: .black.opacity(0.25 * progress), radius: 18 * progress, x: -8 * progress)
            .animation(.smooth(duration: 0.2), value: progress)
    }
}

extension View {
    func pageCurl(progress: Double) -> some View {
        modifier(PageCurl(progress: progress))
    }
}

/// The flip that completes a committed turn: the old art page swings over the spine.
struct PageFlipTransition: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .rotation3DEffect(
                .degrees(phase == .didDisappear ? -180 : 0),
                axis: (x: 0, y: 1, z: 0),
                anchor: .leading,
                perspective: 0.55
            )
            .opacity(phase == .willAppear ? 0 : 1)
    }
}
