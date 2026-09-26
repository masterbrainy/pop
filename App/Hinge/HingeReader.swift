import PopKit
import SwiftUI

extension View {
    /// Feeds the Duo's hinge into `model`. A nil hinge is brief on a Duo (the view is moving
    /// between hierarchies), so it's skipped and the last posture is kept (ROADMAP §2).
    func readsHinge(into model: HingeModel) -> some View {
        onHingeChange { _, context in
            guard let hinge = context.hinge else { return }
            model.ingest(posture: HingePosture(hinge.status), degrees: hinge.angle.degrees, from: .device)
        }
    }
}

extension HingePosture {
    /// `DeviceHinge.Status` is a struct with static members, not an enum (ROADMAP §3).
    init(_ status: DeviceHinge.Status) {
        if status == .closed {
            self = .closed
        } else if status == .fullyOpen {
            self = .fullyOpen
        } else {
            self = .partiallyOpen
        }
    }
}
