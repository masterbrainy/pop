import Foundation
import Testing
@testable import PopKit

/// Covers the wire types in Server/API.swift: exact camelCase field names
/// (docs/CONTRACTS.md §3), round-trips, and the domain-model adapters.
struct APITests {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private func object(from data: Data) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    @Test func storyTurnRequestEncodesContractFieldNamesForPathMode() throws {
        let request = StoryTurnRequest(
            mode: .path,
            bookId: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            kid: StoryTurnKid(firstName: "Maya", readingLevel: .earlyReader, interests: ["dinosaurs"]),
            brief: StoryBrief(interests: ["dinosaurs"], teach: "sharing"),
            settings: ParentSettings(),
            bible: .empty,
            pages: [StoryTurnPageRef(index: 0, text: "Once upon a time")],
            input: StoryTurnInput(kind: .speech, speaker: .parent, text: "a dragon appears"),
            index: 1
        )
        let json = try object(from: encoder.encode(request))
        #expect(json["mode"] as? String == "path")
        #expect(json["index"] as? Int == 1)
        #expect(json["bookId"] as? String == "00000000-0000-0000-0000-000000000001")
        let kid = json["kid"] as? [String: Any]
        #expect(kid?["firstName"] as? String == "Maya")
        #expect(kid?["readingLevel"] as? String == "early_reader")
        let input = json["input"] as? [String: Any]
        #expect(input?["kind"] as? String == "speech")
        #expect(input?["speaker"] as? String == "parent")
        #expect(json["current"] == nil)
    }

    @Test func storyTitleRequestOmitsInputAndIndex() throws {
        let request = StoryTurnRequest.title(
            bookId: UUID(), kid: StoryTurnKid(firstName: "Rex", readingLevel: .reader, interests: []),
            brief: StoryBrief(interests: []), settings: ParentSettings(), bible: .empty, pages: []
        )
        let json = try object(from: encoder.encode(request))
        #expect(json["mode"] as? String == "title")
        #expect(json["input"] == nil)
        #expect(json["index"] == nil)
    }

    @Test func storyTurnKidAdapterDropsTheIdField() throws {
        let kid = KidProfile(firstName: "Maya", readingLevel: .listener, interests: ["stars"])
        let wire = StoryTurnKid(kid)
        let json = try object(from: encoder.encode(wire))
        #expect(json["id"] == nil)
        #expect(json["firstName"] as? String == "Maya")
        #expect(json["readingLevel"] as? String == "listener")
    }

    @Test func storyTurnPageRefAdapterCarriesOnlyIndexAndText() throws {
        let page = PageContent(index: 2, text: "The fox ran home", artPrompt: "a fox running")
        let ref = StoryTurnPageRef(page)
        #expect(ref.index == 2)
        #expect(ref.text == "The fox ran home")
    }

    @Test func storyTurnResponseDecodesAPageWithAnEndingFlagAndNoBreakSuggested() throws {
        let json = Data(#"""
        {
          "action": "page",
          "page": { "index": 1, "text": "The fox found a friend.", "artPrompt": "a fox and a rabbit", "isEnding": true },
          "bible": { "title": null, "setting": "a forest", "characters": [], "directions": ["make it rain"] },
          "parentNote": null,
          "timings": { "modelMs": 812, "safetyMs": 40 }
        }
        """#.utf8)
        let response = try decoder.decode(StoryTurnResponse.self, from: json)
        #expect(response.action == .page)
        #expect(response.page?.isEnding == true)
        #expect(response.bible.directions == ["make it rain"])
        #expect(response.parentNote == nil)
        #expect(response.timings == StoryTurnTimings(modelMs: 812, safetyMs: 40))
    }

    @Test func storyTurnResponseDecodesAPageWithNoEndingFlagAndAnActionOfNone() throws {
        let withoutEnding = Data(#"""
        { "action": "page", "page": { "index": 0, "text": "Once upon a time.", "artPrompt": "a meadow" },
          "bible": { "title": null, "setting": "", "characters": [], "directions": [] },
          "parentNote": null, "timings": { "modelMs": 0, "safetyMs": 0 } }
        """#.utf8)
        let page = try decoder.decode(StoryTurnResponse.self, from: withoutEnding)
        #expect(page.page?.isEnding == nil)

        let refused = Data(#"""
        { "action": "none", "page": null, "bible": { "title": null, "setting": "", "characters": [], "directions": [] },
          "parentNote": "let's try something else", "timings": { "modelMs": 0, "safetyMs": 0 } }
        """#.utf8)
        let none = try decoder.decode(StoryTurnResponse.self, from: refused)
        #expect(none.action == .none)
        #expect(none.parentNote == "let's try something else")
    }

    @Test func artRequestAndResponseRoundTrip() throws {
        let request = ArtRequest(
            bookId: UUID(), kind: .cutout, pageIndex: 2, version: 1, prompt: "a fox on green",
            characters: [Character(id: "fox", name: "Fox", description: "a small red fox")], characterId: "fox"
        )
        let json = try object(from: encoder.encode(request))
        #expect(json["kind"] as? String == "cutout")
        #expect(json["characterId"] as? String == "fox")

        let response = try decoder.decode(
            ArtResponse.self,
            from: Data(#"{"path":"u/b/p2.png","url":"https://x","width":1344,"height":768,"placeholder":false,"ms":900}"#.utf8)
        )
        #expect(response.width == 1344 && response.placeholder == false)
    }

    @Test func artRequestEncodesTheDrawingKindAndItsBase64Field() throws {
        let request = ArtRequest(
            bookId: UUID(), kind: .drawing, version: 1, prompt: "a purple cat with wings",
            characterId: "hero", drawing: "AAA="
        )
        let json = try object(from: encoder.encode(request))
        #expect(json["kind"] as? String == "drawing")
        #expect(json["characterId"] as? String == "hero")
        #expect(json["drawing"] as? String == "AAA=")
        #expect(json["prompt"] as? String == "a purple cat with wings")
    }

    @Test func artRequestOmitsTheDrawingFieldWhenThereIsNoDrawing() throws {
        let request = ArtRequest(bookId: UUID(), kind: .character, prompt: "a fox")
        let json = try object(from: encoder.encode(request))
        #expect(json["drawing"] == nil)
    }

    @Test func moderateRequestEncodesEitherTextOrImage() throws {
        let textJSON = try object(from: encoder.encode(ModerateRequest.text("hello")))
        #expect(textJSON["text"] as? String == "hello")
        #expect(textJSON["imageBase64"] == nil)

        let imageJSON = try object(from: encoder.encode(ModerateRequest.image(base64: "AAA=", mimeType: "image/jpeg")))
        #expect(imageJSON["imageBase64"] as? String == "AAA=")
        #expect(imageJSON["mimeType"] as? String == "image/jpeg")
    }

    @Test func reactorTokenRequestVariantsEncodeTheirOwnAction() throws {
        #expect(try object(from: encoder.encode(ReactorTokenRequest.mint()))["action"] as? String == "mint")
        let report = try object(from: encoder.encode(ReactorTokenRequest.report(sessionId: "s-1")))
        #expect(report["action"] as? String == "report")
        #expect(report["sessionId"] as? String == "s-1")
        #expect(try object(from: encoder.encode(ReactorTokenRequest.cleanup()))["action"] as? String == "cleanup")
    }

    /// The deployed `reactor-token` sends `expiresAt` in milliseconds; the app reads seconds.
    /// Anything above 1e12 can only be milliseconds (1e12 s is the year 33658).
    @Test func reactorMintExpiryInMillisecondsIsReadAsSeconds() throws {
        let millis = try decoder.decode(ReactorMintResponse.self, from: Data(#"{"jwt":"j","expiresAt":1790000000123}"#.utf8))
        #expect(millis.expiresAt == 1_790_000_000.123)
        let seconds = try decoder.decode(ReactorMintResponse.self, from: Data(#"{"jwt":"j","expiresAt":1790000000}"#.utf8))
        #expect(seconds.expiresAt == 1_790_000_000)
        #expect(ReactorMintResponse(jwt: "j", expiresAt: 1_790_000_000_000).expiresAt == 1_790_000_000)
    }

    @Test func motionPromptResponseDecodesAsMotionParts() throws {
        let parts = try decoder.decode(MotionParts.self, from: Data(#"{"scene":"a quiet meadow","motion":"grass sways"}"#.utf8))
        #expect(parts == MotionParts(scene: "a quiet meadow", motion: "grass sways"))
    }

    @Test func emptyPayloadEncodesAndDecodesAsAnEmptyObject() throws {
        let json = try object(from: encoder.encode(EmptyPayload()))
        #expect(json.isEmpty)
        _ = try decoder.decode(EmptyPayload.self, from: Data("{}".utf8))
    }
}
