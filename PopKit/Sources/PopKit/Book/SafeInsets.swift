import CoreGraphics

/// Extra padding that keeps a page's text and faces clear of the fold and the camera
/// (PRD P1/P2), computed from `GeometryProxy.reservedRegions` frames in the pane's space.
public struct SafeInsets: Sendable, Equatable {
    public let top: CGFloat
    public let leading: CGFloat
    public let bottom: CGFloat
    public let trailing: CGFloat

    public init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    public static let zero = SafeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)

    /// Each region pushes the content in from the pane edge it's closest to; overlapping
    /// regions keep the largest push per edge.
    public static func avoiding(_ regions: [CGRect], in size: CGSize) -> SafeInsets {
        let pane = CGRect(origin: .zero, size: size)
        return regions.reduce(SafeInsets.zero) { insets, region in
            let overlap = region.intersection(pane)
            guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { return insets }
            return insets.merging(push(for: overlap, in: pane))
        }
    }

    private static func push(for overlap: CGRect, in pane: CGRect) -> SafeInsets {
        let distances: [(CGFloat, SafeInsets)] = [
            (overlap.minY - pane.minY, SafeInsets(top: overlap.maxY - pane.minY, leading: 0, bottom: 0, trailing: 0)),
            (overlap.minX - pane.minX, SafeInsets(top: 0, leading: overlap.maxX - pane.minX, bottom: 0, trailing: 0)),
            (pane.maxY - overlap.maxY, SafeInsets(top: 0, leading: 0, bottom: pane.maxY - overlap.minY, trailing: 0)),
            (pane.maxX - overlap.maxX, SafeInsets(top: 0, leading: 0, bottom: 0, trailing: pane.maxX - overlap.minX)),
        ]
        // A full-height strip touches top and bottom too; prefer the side whose push is smallest.
        let touching = distances.filter { $0.0 <= 0.5 }
        let candidates = touching.isEmpty ? distances : touching
        return candidates.min { $0.1.total < $1.1.total }?.1 ?? .zero
    }

    private var total: CGFloat { top + leading + bottom + trailing }

    private func merging(_ other: SafeInsets) -> SafeInsets {
        SafeInsets(top: max(top, other.top), leading: max(leading, other.leading), bottom: max(bottom, other.bottom), trailing: max(trailing, other.trailing))
    }
}
