import Foundation
import Testing
@testable import PopKit

/// Covers `Envelope.decode`, the single `{ok,data}` / `{ok,error}` shape every
/// Edge Function reply uses (docs/CONTRACTS.md §3).
struct EnvelopeTests {
    private struct Payload: Codable, Equatable, Sendable {
        let title: String
    }

    @Test func decodesASuccessfulEnvelope() {
        let json = Data(#"{"ok":true,"data":{"title":"Rex Learns to Share"}}"#.utf8)
        let result = Envelope.decode(json, as: Payload.self)
        #expect(result == .success(Payload(title: "Rex Learns to Share")))
    }

    @Test func decodesEachKnownServerErrorCode() {
        let cases: [(String, ServerError)] = [
            ("unauthorized", .unauthorized("nope")),
            ("forbidden", .forbidden("nope")),
            ("rate_limited", .rateLimited("nope")),
            ("bad_request", .badRequest("nope")),
            ("unsafe", .unsafe("nope")),
            ("upstream", .upstream("nope")),
            ("internal", .internalError("nope")),
        ]
        for (code, expected) in cases {
            let json = Data(#"{"ok":false,"error":{"code":"\#(code)","message":"nope"}}"#.utf8)
            let result = Envelope.decode(json, as: Payload.self)
            #expect(result == .failure(expected))
        }
    }

    @Test func unrecognizedErrorCodeFallsBackToInternal() {
        let json = Data(#"{"ok":false,"error":{"code":"teapot","message":"I'm a teapot"}}"#.utf8)
        let result = Envelope.decode(json, as: Payload.self)
        #expect(result == .failure(.internalError("I'm a teapot")))
    }

    @Test func malformedJSONDecodesToADecodingError() {
        let json = Data(#"{ not json"#.utf8)
        let result = Envelope.decode(json, as: Payload.self)
        guard case .failure(.decoding) = result else {
            Issue.record("expected a decoding failure, got \(result)")
            return
        }
    }

    @Test func okTrueWithAPayloadThatDoesNotMatchTypeDecodesToADecodingError() {
        let json = Data(#"{"ok":true,"data":{"nope":1}}"#.utf8)
        let result = Envelope.decode(json, as: Payload.self)
        guard case .failure(.decoding) = result else {
            Issue.record("expected a decoding failure, got \(result)")
            return
        }
    }

    @Test func okTrueWithNoDataAndOkFalseWithNoErrorBothDecodeToADecodingError() {
        #expect(Envelope.decode(Data(#"{"ok":true}"#.utf8), as: Payload.self).isDecodingFailure)
        #expect(Envelope.decode(Data(#"{"ok":false}"#.utf8), as: Payload.self).isDecodingFailure)
    }

    @Test func serverErrorMessagesAreUserFriendlyAndNeverTheRawServerText() {
        let raw = "duplicate key value violates unique constraint \"pages_book_id_index_version_key\""
        let error = ServerError.internalError(raw)
        #expect(error.message != raw)
        #expect(!error.message.isEmpty)
        #expect(error.serverDetail == raw)
    }

    @Test func transportAndDecodingErrorsCarryTheirOwnFriendlyMessage() {
        #expect(!ServerError.transport("URLError(-1009)").message.isEmpty)
        #expect(!ServerError.decoding("keyNotFound(title)").message.isEmpty)
    }
}

private extension Result where Failure == ServerError {
    var isDecodingFailure: Bool {
        guard case .failure(let error) = self, case .decoding = error else { return false }
        return true
    }
}

@Suite struct WholeNumberDecodingTests {
    @Test func timingsWithFractionsRoundToWholeMilliseconds() throws {
        let json = Data(#"{"modelMs": 2298.6833770000003, "safetyMs": 12}"#.utf8)
        let timings = try JSONDecoder().decode(StoryTurnTimings.self, from: json)
        #expect(timings == StoryTurnTimings(modelMs: 2299, safetyMs: 12))
    }

    @Test func artResponseAcceptsAFractionalMs() throws {
        let json = Data(#"{"path":"u/b/p.png","url":"https://x","width":1344,"height":768,"placeholder":false,"ms":5012.4}"#.utf8)
        let art = try JSONDecoder().decode(ArtResponse.self, from: json)
        #expect(art.ms == 5012)
        #expect(art.width == 1344)
    }
}
