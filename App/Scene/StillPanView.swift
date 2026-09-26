import PopKit
import SwiftUI

/// The fallback living page (`StillPanScene`): the still drifts in a slow pan and zoom, so a
/// page still feels alive when Orbis is off, failed, or hasn't started yet. It rests at the
/// identity transform, which is how the live video (and a saved clip) is drawn on top, so
/// when video takes over the still eases back to identity during the one crossfade instead
/// of snapping (`StillPanMotion`).
struct StillPanView: View {
    let image: UIImage
    var isMoving = true

    @State private var motion = StillPanMotion.resting
    /// False once the still has settled, so the timeline stops redrawing under the video.
    @State private var isTicking = false

    var body: some View {
        TimelineView(.animation(paused: !isTicking)) { context in
            let amount = motion.amount(at: context.date)
            GeometryReader { proxy in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .scaleEffect(StillPanMotion.scale(for: amount))
                    .offset(x: proxy.size.width * StillPanMotion.offsetFraction(for: amount))
                    .clipped()
            }
        }
        .task(id: isMoving) {
            let now = Date()
            if isMoving {
                motion = motion.moving(at: now)
                isTicking = true
                return
            }
            motion = motion.settling(at: now)
            guard !motion.isSettled(at: now) else {
                isTicking = false
                return
            }
            isTicking = true
            try? await Task.sleep(for: .seconds(StillPanMotion.settleDuration))
            if !Task.isCancelled { isTicking = false }
        }
        .accessibilityHidden(true)
    }
}
