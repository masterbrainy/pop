import Foundation
import Testing
@testable import PopKit

/// IMP-24: the guided setup's answers travel on the brief (tiles as ids, words as text), old
/// books still load, and a book's own answers beat the kid profile's interests.
struct GuidedBriefTests {
    private let kid = KidProfile(firstName: "Maya", readingLevel: .earlyReader, interests: ["foxes", "stars"])

    private func json(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - wire shape

    @Test func aTileAnswerTravelsAsItsIdOnly() throws {
        let brief = StoryBrief(interests: [], hero: .tile("dragon"))
        let hero = try #require(try json(brief)["hero"] as? [String: Any])
        #expect(hero as NSDictionary == ["tile": "dragon"] as NSDictionary)
    }

    @Test func aSpokenAnswerTravelsAsTextWithItsSource() throws {
        let brief = StoryBrief(interests: [], place: .text("under my bed", via: .speech))
        let place = try #require(try json(brief)["place"] as? [String: Any])
        #expect(place as NSDictionary == ["text": "under my bed", "via": "speech"] as NSDictionary)
    }

    @Test func moodAndPurposeUseTheContractsNames() throws {
        let object = try json(StoryBrief(interests: [], mood: .cosy, purpose: .realMoment))
        #expect(object["mood"] as? String == "cosy")
        #expect(object["purpose"] as? String == "realMoment")
    }

    @Test func unansweredCardsAreLeftOffTheWire() throws {
        let object = try json(StoryBrief(interests: ["boats"]))
        #expect(object["hero"] == nil)
        #expect(object["mood"] == nil)
        #expect(object["purpose"] == nil)
    }

    @Test func aBriefRoundTripsThroughJSON() throws {
        let brief = StoryBrief(interests: ["boats"], realMoment: "a new baby", hero: .tile("kid"), place: .text("the moon", via: .typed),
                               problem: .tile("lost"), mood: .silly, purpose: .fun)
        let decoded = try JSONDecoder().decode(StoryBrief.self, from: JSONEncoder().encode(brief))
        #expect(decoded == brief)
    }

    @Test func briefsSavedBeforeTheCardsStillLoad() throws {
        let old = #"{"interests":["foxes"],"realMoment":null,"teach":"sharing","language":"en"}"#
        let brief = try JSONDecoder().decode(StoryBrief.self, from: Data(old.utf8))
        #expect(brief.interests == ["foxes"])
        #expect(brief.teach == "sharing")
        #expect(brief.hero == nil)
        #expect(brief.mood == nil)
    }

    @Test func typedOrSpokenAnswersAreTrimmedAndCappedAt80Characters() {
        #expect(BriefAnswer.answer(text: "   ", via: .typed) == nil)
        #expect(BriefAnswer.answer(text: "  a purple cat  ", via: .speech) == .text("a purple cat", via: .speech))
        let long = String(repeating: "a", count: 120)
        guard case let .text(capped, _)? = BriefAnswer.answer(text: long, via: .typed) else {
            Issue.record("expected a text answer")
            return
        }
        #expect(capped.count == 80)
    }

    // MARK: - addingInterest keeps the cards (it used to rebuild the brief field by field)

    @Test func addingAnInterestKeepsEveryCardAnswer() {
        let brief = StoryBrief(interests: [], realMoment: "moving house", teach: "sharing", language: "es", hero: .tile("dragon"),
                               place: .tile("pond"), problem: .text("the boat sank", via: .typed), mood: .brave, purpose: .teach)
        let added = brief.addingInterest("a purple cat")
        #expect(added.interests == ["a purple cat"])
        #expect(added == brief.with(interests: ["a purple cat"]))
        #expect(added.hero == .tile("dragon"))
        #expect(added.mood == .brave)
        #expect(added.purpose == .teach)
        #expect(added.language == "es")
    }

    // MARK: - book interests win (the sample profile's "foxes, stars" must not leak into every book)

    @Test func theProfilesInterestsStayHomeWhenTheBookHasItsOwnCards() {
        let book = Book(kidId: kid.id, brief: StoryBrief(interests: [], hero: .tile("dragon")), createdAt: .now)
        let request = StoryEngine.pathRequest(book: book, kid: kid, settings: ParentSettings(), shownPages: [], index: 0, input: nil)
        #expect(request.kid.interests.isEmpty)
    }

    @Test func theProfilesInterestsStayHomeWhenTheBookHasItsOwnInterests() {
        let book = Book(kidId: kid.id, brief: StoryBrief(interests: ["boats"]), createdAt: .now)
        let request = StoryEngine.pageRequest(book: book, kid: kid, settings: ParentSettings(), shownPages: [], index: 1)
        #expect(request.kid.interests.isEmpty)
        #expect(request.brief.interests == ["boats"])
    }

    @Test func aBookWithNoAnswersStillLeansOnTheProfile() {
        let book = Book(kidId: kid.id, brief: StoryBrief(interests: [], mood: .silly), createdAt: .now)
        let request = StoryEngine.pathRequest(book: book, kid: kid, settings: ParentSettings(), shownPages: [], index: 0, input: nil)
        #expect(request.kid.interests == ["foxes", "stars"])
    }

    @Test func theSampleProfilesInterestsAreDroppedForNewBooks() {
        #expect(SampleBooks.kid.droppingSampleInterests().interests.isEmpty)
        #expect(SampleBooks.kid.droppingSampleInterests().firstName == SampleBooks.kid.firstName)
        let own = KidProfile(firstName: "Ari", readingLevel: .reader, interests: ["foxes", "trains"])
        #expect(own.droppingSampleInterests() == own)
        #expect(SampleBooks.fox.brief.interests == ["foxes", "stars"], "the sample book itself is unchanged")
    }
}
