import Foundation

/// A kid's own finger drawing of their story's hero, exported as a PNG (ROADMAP Phase 8.2).
/// Kept as raw bytes here so `HeroCharacter` can build the `art` request's base64 field;
/// the app is responsible for actually rendering and sizing the PNG (docs/CONTRACTS.md §3).
public struct HeroDrawing: Equatable, Sendable {
    public let imageData: Data
    /// What the drawing is, in the kid's or parent's own words (e.g. "a purple cat with wings").
    public let description: String

    public init(imageData: Data, description: String) {
        self.imageData = imageData
        self.description = description
    }

    public var base64: String { imageData.base64EncodedString() }
}
