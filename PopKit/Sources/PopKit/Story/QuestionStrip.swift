import Foundation

/// The question showing under the page while a book is being made (IMP-25).
public struct ActiveQuestion: Equatable, Sendable {
    /// The page (and version) it belongs to, so answering it settles only this one.
    public let page: PageKey
    public let ask: String
    public let kind: QuestionKind
    public let choices: [StoryChoice]

    public init(page: PageKey, ask: String, kind: QuestionKind, choices: [StoryChoice]) {
        self.page = page
        self.ask = ask
        self.kind = kind
        self.choices = choices
    }
}

/// When the question strip shows, and what a tapped choice sends (IMP-25). The parent reads
/// the question aloud; the kid answers by tapping, talking, or "something else".
public enum QuestionStrip {
    /// The longest direction a choice may send (the server's cap for `input.kind: "choice"`).
    public static let maxChoiceLength = 120

    /// The page's question, unless there's nothing to ask yet, it's the ending, a direction is
    /// re-writing the page behind (the question may be stale), or it was answered, skipped or
    /// made stale by a re-plan (`settled` holds those pages' keys).
    public static func visible(page: PageContent?, isEnding: Bool, directionInFlight: Bool, settled: Set<PageKey>) -> ActiveQuestion? {
        guard let page, !page.text.isEmpty, !isEnding, !directionInFlight, !settled.contains(page.key),
              let ask = page.question, !ask.isEmpty
        else { return nil }
        let choices = page.choices ?? []
        return ActiveQuestion(page: page.key, ask: ask, kind: page.questionKind ?? (choices.isEmpty ? .talkOnly : .choice), choices: choices)
    }

    /// What tapping `choice` sends: nothing when it's already the path's next beat (the page
    /// behind is being built that way), else the kid's choice as a turn of its own.
    public static func input(for choice: StoryChoice) -> StoryTurnInput? {
        guard !choice.followsPath else { return nil }
        let direction = choice.direction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !direction.isEmpty else { return nil }
        return StoryTurnInput(kind: .choice, speaker: .kid, text: String(direction.prefix(maxChoiceLength)))
    }
}
