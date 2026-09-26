import Foundation

/// How long the app waits on each Edge Function before giving up, so a hung call fails
/// into the normal error path instead of leaving "Painting…" on screen for a minute or
/// more (IMP-10). `URLRequest.timeoutInterval` is an idle timeout, and these functions
/// send nothing until their reply is ready, so in practice it bounds the whole call.
public enum PopServerTimeouts {
    public static let storyTurn: TimeInterval = 25
    public static let art: TimeInterval = 45
    public static let motionPrompt: TimeInterval = 20
    public static let moderate: TimeInterval = 8
    /// Sign-in, token mints, speech: small replies that should come back quickly.
    public static let standard: TimeInterval = 15
    /// Downloading a finished picture from its signed URL.
    public static let mediaDownload: TimeInterval = 30

    public static func seconds(for function: String) -> TimeInterval {
        switch function {
        case "story-turn": storyTurn
        case "art": art
        case "motion-prompt": motionPrompt
        case "moderate": moderate
        default: standard
        }
    }
}
