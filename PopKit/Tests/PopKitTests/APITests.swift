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

    @Test func storyTurnRequestEncodesContractFieldNamesForTurnMode() throws {
        let request = StoryTurnRequest.turn(
            bookId: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            kid: StoryTurnKid(firstName: "Maya", readingLevel: .earlyReader, interests: ["dinosaurs"]),
            brief: StoryBrief(interests: ["dinosaurs"], teach: "sharing"),
            settings: ParentSettings(),
            bible: .empty,
            pages: [StoryTurnPageRef(index: 0, text: "Once upon a time")],
            current: StoryTurnCurrent(index: 1, text: ""),
            input: StoryTurnInput(kind: .speech, speaker: .parent, text: "a dragon appears")
        )
        let json = try object(from: encoder.encode(request))
        #expect(json["mode"] as? String == "turn")
        #expect(json["bookId"] as? String == "00000000-0000-0000-0000-000000000001")
        let kid = json["kid"] as? [String: Any]
        #expect(kid?["firstName"] as? String == "Maya")
        #expect(kid?["readingLevel"] as? String == "early_reader")
        let input = json["input"] as? [String: Any]
        #expect(input?["kind"] as? String == "speech")
        #expect(input?["speaker"] as? String == "parent")
        #expect(json["current"] != nil)
    }

    @Test func storyTitleRequestOmitsCurrentAndInput() throws {
        let request = StoryTurnRequest.title(
            bookId: UUID(), kid: StoryTurnKid(firstName: "Rex", readingLevel: .reader, interests: []),
            brief: StoryBrief(interests: []), settings: ParentSettings(), bible: .empty, pages: []
        )
        let json = try object(from: encoder.encode(request))
        #expect(json["mode"] as? String == "title")
        #expect(json["current"] == nil)
        #expect(json["input"] == nil)
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

    @Test func storyTurnResponseDecodesEveryAction() throws {
        let json = Data(#"""
        {
          "action": "new_page",
          "page": { "index": 1, "text": "The fox found a friend.", "artPrompt": "a fox and a rabbit", "breakSuggested": true },
          "bible": { "title": null, "setting": "a forest", "characters": [], "directions": ["make it rain"] },
          "parentNote": null,
          "timings": { "modelMs": 812, "safetyMs": 40 }
        }
        """#.utf8)
        let response = try decoder.decode(StoryTurnResponse.self, from: json)
        #expect(response.action == .newPage)
        #expect(response.page?.breakSuggested == true)
        #expect(response.bible.directions == ["make it rain"])
        #expect(response.parentNote == nil)
        #expect(response.timings == StoryTurnTimings(modelMs: 812, safetyMs: 40))

        for action in ["append", "revise_current", "none"] {
            let variant = Data(#"""
            { "action": "\#(action)", "page": null, "bible": { "title": null, "setting": "", "characters": [], "directions": [] },
              "parentNote": "let's try something else", "timings": { "modelMs": 0, "safetyMs": 0 } }
            """#.utf8)
            _ = try decoder.decode(StoryTurnResponse.self, from: variant)
        }
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
