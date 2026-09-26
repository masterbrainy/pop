import Foundation
import Testing
@testable import PopKit

/// IMP-24: the guided setup's picture cards. 2 tiles for Listeners (working memory holds about
/// 2–3 items around age 5), 3 for older kids (the view adds "something else"), either/or only.
struct SetupCardsTests {
    private let noInterests = KidProfile(firstName: "Maya", readingLevel: .listener, interests: [])
    private let empty = StoryBrief(interests: [])

    /// A fixed generator, so "Surprise me" is testable.
    private struct Sequence: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    @Test func listenersSeeTwoTilesAndOlderKidsThree() {
        for card in SetupCard.allCases {
            #expect(SetupCards.options(card: card, level: .listener, brief: empty, kid: noInterests).count == 2)
            #expect(SetupCards.options(card: card, level: .earlyReader, brief: empty, kid: noInterests).count == 3)
            #expect(SetupCards.options(card: card, level: .reader, brief: empty, kid: noInterests).count == 3)
        }
    }

    @Test func optionsOnlyOfferTilesForThatCardAndLevel() {
        for level in ReadingLevel.allCases {
            for card in SetupCard.allCases {
                for tile in SetupCards.options(card: card, level: level, brief: empty, kid: noInterests) {
                    #expect(tile.card == card)
                    #expect(tile.levels.contains(level))
                }
            }
        }
    }

    @Test func theChildIsAlwaysTheFirstHero() {
        let hero = SetupCards.options(card: .hero, level: .listener, brief: empty, kid: noInterests)
        #expect(hero.first?.id == "kid")
    }

    @Test func aProfileFavouriteIsOfferedAsATileNotSentAsInterests() {
        let kid = KidProfile(firstName: "Maya", readingLevel: .earlyReader, interests: ["Dinosaurs", "Rabbits", "the seaside"])
        let hero = SetupCards.options(card: .hero, level: .earlyReader, brief: empty, kid: kid).map(\.id)
        #expect(hero == ["kid", "dragon", "bunny"])
        let place = SetupCards.options(card: .place, level: .earlyReader, brief: empty, kid: kid).map(\.id)
        #expect(place.first == "beach")
    }

    @Test func optionsAreStableForTheSameInput() {
        let first = SetupCards.options(card: .problem, level: .reader, brief: empty, kid: noInterests)
        let second = SetupCards.options(card: .problem, level: .reader, brief: empty, kid: noInterests)
        #expect(first == second)
    }

    @Test func surpriseMePicksATileThisLevelCanHave() {
        var rng = Sequence(state: 7)
        for _ in 0..<50 {
            let tile = SetupCards.surprise(card: .problem, level: .listener, rng: &rng)
            #expect(tile?.card == .problem)
            #expect(tile?.levels.contains(.listener) == true)
        }
    }

    @Test func surpriseMeReachesManyTiles() {
        var rng = Sequence(state: 1)
        let picks = Set((0..<40).compactMap { _ in SetupCards.surprise(card: .hero, level: .reader, rng: &rng)?.id })
        #expect(picks.count > 3)
    }

    @Test func listenersGetTwoMoodsAndOlderKidsThree() {
        #expect(SetupCards.moods(for: .listener) == [.silly, .cosy])
        #expect(SetupCards.moods(for: .reader) == [.silly, .cosy, .brave])
    }

    // MARK: - matching speech to a tile

    @Test func aSpokenWordMatchesTheTileItNames() {
        let options = SetupCards.options(card: .place, level: .listener, brief: empty, kid: noInterests)
        #expect(options.map(\.id) == ["forest", "beach"])
        #expect(SetupCards.match(spoken: "The BEACH please!", options: options)?.id == "beach")
        #expect(SetupCards.match(spoken: "in the woods", options: options)?.id == "forest")
    }

    @Test func speechThatNamesNoOptionMatchesNothing() {
        let options = SetupCards.options(card: .place, level: .listener, brief: empty, kid: noInterests)
        #expect(SetupCards.match(spoken: "a volcano made of jelly", options: options) == nil)
        #expect(SetupCards.match(spoken: "", options: options) == nil)
    }

    @Test func aWordInsideAnotherWordIsNotAMatch() {
        let options = [SetupCards.tile(id: "cat")!]
        #expect(SetupCards.match(spoken: "a caterpillar", options: options) == nil)
        #expect(SetupCards.match(spoken: "a cat", options: options)?.id == "cat")
    }

    @Test func theChildCanPickThemselvesByNameOrByMe() {
        let options = SetupCards.options(card: .hero, level: .listener, brief: empty, kid: noInterests)
        #expect(SetupCards.match(spoken: "me!", options: options)?.id == "kid")
        #expect(SetupCards.match(spoken: "Maya", options: options, kidName: "Maya")?.id == "kid")
    }

    // MARK: - scripted runs (-setup)

    @Test func aSetupScriptBecomesABrief() {
        let brief = SetupCards.brief(fromScript: "hero:kid, place:pond,problem:lost,mood:silly,purpose:bedtime")
        #expect(brief.hero == .tile("kid"))
        #expect(brief.place == .tile("pond"))
        #expect(brief.problem == .tile("lost"))
        #expect(brief.mood == .silly)
        #expect(brief.purpose == .bedtime)
        #expect(brief.interests.isEmpty)
    }

    @Test func aScriptAnswerThatIsNoTileIsTypedText() {
        let brief = SetupCards.brief(fromScript: "hero:a purple cat with wings,mood:grumpy,nonsense")
        #expect(brief.hero == .text("a purple cat with wings", via: .typed))
        #expect(brief.mood == nil)
    }

    @Test func aTileOnTheWrongCardIsTypedText() {
        #expect(SetupCards.brief(fromScript: "place:dragon").place == .text("dragon", via: .typed))
    }
}
