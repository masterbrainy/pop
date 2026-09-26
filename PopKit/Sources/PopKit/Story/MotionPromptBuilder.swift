import Foundation

/// Builds the Orbis prompt for one page from a fixed template (ROADMAP §2). The scene and
/// camera stay identical within the page; only one gentle motion clause varies. This applies
/// the teammate's continuity lesson: nothing new enters, no cuts.
public enum MotionPromptBuilder {
    static let defaultMotion = "Everything sways very gently"
    /// Closes every Orbis prompt: the live video drifts toward a photoreal look the longer it
    /// runs, so the locked picture-book style is restated as the last thing it reads.
    static let styleHold = "Keep the soft watercolor and colored pencil picture-book look the whole time, exactly as in the picture: never photoreal, never 3D, the same colours and outlines."

    public static func prompt(scene: String, motion: String) -> String {
        let sceneText = withoutLeadingArticle(tidy(scene))
        let motionText = tidy(motion)
        let clause = sentence(motionText.isEmpty ? defaultMotion : motionText)
        return "The same \(sceneText.isEmpty ? "scene" : sceneText), the same locked-off, still camera. \(clause) Nothing new enters the scene. Continuous slow motion, no cuts. \(styleHold)"
    }

    public static func prompt(_ parts: MotionParts) -> String {
        prompt(scene: parts.scene, motion: parts.motion)
    }

    private static func tidy(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!;,"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func withoutLeadingArticle(_ text: String) -> String {
        let lowered = text.lowercased()
        for article in ["the ", "a ", "an "] where lowered.hasPrefix(article) {
            return String(text.dropFirst(article.count))
        }
        return text
    }

    private static func sentence(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst() + "."
    }
}
