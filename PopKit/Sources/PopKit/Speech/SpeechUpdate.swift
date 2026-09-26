import Foundation

/// What a speech recogniser reports while the parent (or kid) tells the story (PRD S1).
public enum SpeechUpdate: Sendable, Equatable {
    /// Someone started saying a new utterance. Its words belong to whoever's turn it is now
    /// (`SpeakerLedger`), even if the turn changes before they're transcribed.
    case began(utterance: String)
    /// Words heard so far and not yet final; replaces the previous partial ("" clears it).
    case partial(String)
    /// A finished utterance, ready to become a story turn.
    case final(String, utterance: String?)
    /// Listening stopped for good; the recogniser has already cleaned up.
    case failed(String)
}

/// Remembers whose turn it was when each utterance began (PRD S3), so a parent's words
/// transcribed after they hand over to the kid still count as the parent's, and the other
/// way round.
public struct SpeakerLedger: Sendable {
    private var speakers: [String: Speaker] = [:]

    public init() {}

    public mutating func began(_ utterance: String, by speaker: Speaker) {
        if speakers[utterance] == nil { speakers[utterance] = speaker }
    }

    /// Who said `utterance`: whoever began it, else `current`. Each utterance is answered once.
    public mutating func speaker(of utterance: String?, current: Speaker) -> Speaker {
        guard let utterance else { return current }
        return speakers.removeValue(forKey: utterance) ?? current
    }
}
