import Foundation
import Testing
@testable import PopKit

@Suite struct FrameTripwireTests {
    private struct Boom: Error {}

    @Test func sendsTheFrameAsAnImageModerationRequest() async {
        let server = FakePopServer()
        let seen = Recorder<ModerateRequest>()
        await server.setModerateHandler { request in
            await seen.add(request)
            return ModerateResponse(flagged: false, categories: [])
        }
        let verdict = await FrameTripwire(server: server).check(base64: "QUJD", mimeType: "image/jpeg")
        #expect(verdict == .clear)
        #expect(await seen.items == [.image(base64: "QUJD", mimeType: "image/jpeg")])
    }

    @Test func aFlaggedFrameReportsItsCategories() async {
        let server = FakePopServer()
        await server.setModerateHandler { _ in ModerateResponse(flagged: true, categories: ["violence"]) }
        let verdict = await FrameTripwire(server: server).check(base64: "QUJD", mimeType: "image/jpeg")
        #expect(verdict == .flagged(["violence"]))
        #expect(verdict.isFlagged)
    }

    @Test func aModerationFailureLeavesTheFrameUncheckedNotFlagged() async {
        let server = FakePopServer()
        await server.setModerateHandler { _ in throw Boom() }
        let verdict = await FrameTripwire(server: server).check(base64: "QUJD", mimeType: "image/jpeg")
        #expect(!verdict.isFlagged)
        if case .unchecked = verdict {} else { Issue.record("expected .unchecked, got \(verdict)") }
    }

    @Test func checksEveryFewSecondsWhileTheClipRecordsThenOnAnInterval() {
        // R-38: every part of the saved 10 s clip is covered by a check.
        let offsets = (0..<6).reduce(into: [Duration]()) { times, index in
            times.append((times.last ?? .zero) + FrameTripwire.delay(beforeCheck: index))
        }
        #expect(offsets == [.seconds(3), .seconds(6), .seconds(9), .seconds(12), .seconds(27), .seconds(42)])
        #expect(FrameTripwire.clipCheckSpacing < FrameTripwire.interval)
    }
}

actor Recorder<Item: Sendable> {
    private(set) var items: [Item] = []
    func add(_ item: Item) { items.append(item) }
}

extension FakePopServer {
    func setModerateHandler(_ handler: @escaping @Sendable (ModerateRequest) async throws -> ModerateResponse) {
        moderateHandler = handler
    }
}
