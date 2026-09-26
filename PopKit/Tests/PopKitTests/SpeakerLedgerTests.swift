import Testing
@testable import PopKit

/// Covers `SpeakerLedger`: spoken words belong to whoever's turn it was when they started
/// speaking, not whoever's turn it is when the transcript arrives a second later (PRD S3).
struct SpeakerLedgerTests {
    @Test func wordsBelongToWhoeverStartedSayingThem() {
        var ledger = SpeakerLedger()
        ledger.began("item_1", by: .parent)

        // The parent hands over to the kid before the transcript lands.
        let speaker = ledger.speaker(of: "item_1", current: .kid)

        #expect(speaker == .parent)
    }

    @Test func theFirstSpeakerOfAnUtteranceKeepsIt() {
        var ledger = SpeakerLedger()
        ledger.began("item_1", by: .kid)
        ledger.began("item_1", by: .parent)

        #expect(ledger.speaker(of: "item_1", current: .parent) == .kid)
    }

    @Test func anUnknownOrMissingUtteranceUsesTheCurrentSpeaker() {
        var ledger = SpeakerLedger()

        #expect(ledger.speaker(of: "never-began", current: .kid) == .kid)
        #expect(ledger.speaker(of: nil, current: .parent) == .parent)
    }

    @Test func anUtteranceIsAnsweredOnce() {
        var ledger = SpeakerLedger()
        ledger.began("item_1", by: .kid)

        _ = ledger.speaker(of: "item_1", current: .parent)

        #expect(ledger.speaker(of: "item_1", current: .parent) == .parent)
    }
}
