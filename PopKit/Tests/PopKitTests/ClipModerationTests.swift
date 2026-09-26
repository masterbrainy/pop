import Foundation
import ImageIO
import Testing
@testable import PopKit

@Suite struct ClipSampleTimesTests {
    @Test func aTenSecondClipIsSampledHalfASecondFromEachEndAndEveryThreeSecondsBetween() {
        #expect(FrameTripwire.clipSampleTimes(duration: 10) == [0.5, 3.5, 6.5, 9.5])
    }

    @Test func aTwoSecondClipIsSampledNearBothEnds() {
        #expect(FrameTripwire.clipSampleTimes(duration: 2) == [0.5, 1.5])
    }

    @Test func aClipShorterThanOneSecondIsSampledOnceInTheMiddle() {
        #expect(FrameTripwire.clipSampleTimes(duration: 0.4) == [0.2])
        #expect(FrameTripwire.clipSampleTimes(duration: 1) == [0.5])
    }

    @Test func anEmptyOrBrokenDurationHasNoSamples() {
        #expect(FrameTripwire.clipSampleTimes(duration: 0).isEmpty)
        #expect(FrameTripwire.clipSampleTimes(duration: -3).isEmpty)
        #expect(FrameTripwire.clipSampleTimes(duration: .nan).isEmpty)
        #expect(FrameTripwire.clipSampleTimes(duration: .infinity).isEmpty)
    }

    @Test(arguments: [0.3, 0.9, 1.2, 2.5, 4, 7.25, 10, 10.4, 30])
    func samplesStayInsideTheClipAndLeaveNoLongGap(duration: Double) {
        let times = FrameTripwire.clipSampleTimes(duration: duration)
        #expect(!times.isEmpty)
        #expect(times.allSatisfy { $0 >= 0 && $0 < duration })
        #expect(times == times.sorted() && Set(times).count == times.count)
        let gaps = zip(times, times.dropFirst()).map { $1 - $0 }
        #expect(gaps.allSatisfy { $0 <= 3.0001 })
    }
}

@Suite struct ClipVerdictTests {
    @Test func anyFlaggedFrameFlagsTheClipWithEveryCategoryOnce() {
        let verdicts: [FrameTripwire.Verdict] = [
            .clear, .flagged(["violence"]), .unchecked("timeout"), .flagged(["sexual", "violence"]),
        ]
        #expect(ClipVerdict.decide(verdicts, pageWasSeenLive: true) == .flagged(["violence", "sexual"]))
        #expect(ClipVerdict.decide(verdicts, pageWasSeenLive: false) == .flagged(["violence", "sexual"]))
    }

    @Test func aFlaggedFrameWithoutCategoriesStillFlags() {
        #expect(ClipVerdict.decide([.clear, .flagged([])], pageWasSeenLive: true) == .flagged([]))
    }

    @Test func noVerdictsLeavesTheClipUnchecked() {
        #expect(ClipVerdict.decide([], pageWasSeenLive: true) == .unchecked("no frames"))
        #expect(ClipVerdict.decide([], pageWasSeenLive: false) == .unchecked("no frames"))
    }

    @Test func anUncheckedFrameFailsClosedOnAPageNobodySaw() {
        #expect(ClipVerdict.decide([.clear, .unchecked("timeout")], pageWasSeenLive: false) == .unchecked("timeout"))
    }

    @Test func anUncheckedFrameOnAPageSeenLiveStillAttaches() {
        // The live tripwire already covered a page someone watched.
        #expect(ClipVerdict.decide([.clear, .unchecked("timeout")], pageWasSeenLive: true) == .attach)
    }

    @Test func allClearAttaches() {
        #expect(ClipVerdict.decide([.clear, .clear], pageWasSeenLive: false) == .attach)
    }
}

@Suite struct ClipModerationTests {
    private struct Boom: Error {}

    private static func tenSecondClip() async throws -> URL {
        let url = SyntheticClip.temporaryURL("moderation")
        try await SyntheticClip.write(to: url, seconds: 10, fps: 10, width: 160, height: 96)
        return url
    }

    @Test func samplesJPEGFramesNoLargerThanMaxSide() async throws {
        let url = SyntheticClip.temporaryURL("sampler")
        try await SyntheticClip.write(to: url, seconds: 2, fps: 10, width: 320, height: 192)
        defer { try? FileManager.default.removeItem(at: url) }
        let frames = try await ClipFrameSampler.frames(from: url, at: [0.5, 1.5], maxSide: 64)
        #expect(frames.count == 2)
        for frame in frames {
            #expect(frame.mimeType == "image/jpeg")
            let data = try #require(Data(base64Encoded: frame.base64))
            #expect(data.prefix(2) == Data([0xFF, 0xD8]))
            let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(max(image.width, image.height) <= 64)
        }
    }

    @Test func aTimeThatCanNotBeReadIsSkipped() async throws {
        let url = SyntheticClip.temporaryURL("sampler-skip")
        try await SyntheticClip.write(to: url, seconds: 2, fps: 10, width: 160, height: 96)
        defer { try? FileManager.default.removeItem(at: url) }
        let frames = try await ClipFrameSampler.frames(from: url, at: [0.5, 60], maxSide: 512)
        #expect(frames.count == 1)
    }

    @Test func aMissingFileCanNotBeSampled() async {
        let missing = SyntheticClip.temporaryURL("missing")
        await #expect(throws: (any Error).self) {
            try await ClipFrameSampler.frames(from: missing, at: [0.5], maxSide: 512)
        }
    }

    @Test func aClearClipAttachesAfterEverySampleIsCheckedInParallel() async throws {
        let url = try await Self.tenSecondClip()
        defer { try? FileManager.default.removeItem(at: url) }
        let server = FakePopServer()
        let seen = Recorder<ModerateRequest>()
        let inFlight = InFlightCounter()
        await server.setModerateHandler { request in
            await seen.add(request)
            await inFlight.enter()
            try await Task.sleep(for: .milliseconds(100))
            await inFlight.leave()
            return ModerateResponse(flagged: false, categories: [])
        }
        let verdict = await FrameTripwire(server: server).checkClip(at: url, pageWasSeenLive: false)
        #expect(verdict == .attach)
        let requests = await seen.items
        #expect(requests.count == FrameTripwire.clipSampleTimes(duration: 10).count)
        #expect(requests.allSatisfy { $0.mimeType == "image/jpeg" && ($0.imageBase64?.isEmpty == false) })
        #expect(Set(requests.compactMap(\.imageBase64)).count == requests.count, "each sample is a different frame")
        #expect(await inFlight.peak > 1, "frames are checked in parallel")
    }

    @Test func oneFlaggedFrameFlagsTheClip() async throws {
        let url = try await Self.tenSecondClip()
        defer { try? FileManager.default.removeItem(at: url) }
        let server = FakePopServer()
        let calls = Recorder<Int>()
        await server.setModerateHandler { _ in
            await calls.add(1)
            let isSecond = await calls.items.count == 2
            return ModerateResponse(flagged: isSecond, categories: isSecond ? ["violence"] : [])
        }
        let verdict = await FrameTripwire(server: server).checkClip(at: url, pageWasSeenLive: true)
        #expect(verdict == .flagged(["violence"]))
        #expect(await calls.items.count == 4)
    }

    @Test func aModerationOutageFailsClosedOnlyForAnUnseenPage() async throws {
        let url = try await Self.tenSecondClip()
        defer { try? FileManager.default.removeItem(at: url) }
        let server = FakePopServer()
        await server.setModerateHandler { _ in throw Boom() }
        let tripwire = FrameTripwire(server: server)
        let unseen = await tripwire.checkClip(at: url, pageWasSeenLive: false)
        if case .unchecked = unseen {} else { Issue.record("expected .unchecked, got \(unseen)") }
        #expect(await tripwire.checkClip(at: url, pageWasSeenLive: true) == .attach)
    }

    @Test func anUnreadableClipFailsClosedOnAnUnseenPage() async {
        let server = FakePopServer()
        await server.setModerateHandler { _ in
            Issue.record("nothing should be sent for an unreadable clip")
            return ModerateResponse(flagged: false, categories: [])
        }
        let verdict = await FrameTripwire(server: server)
            .checkClip(at: SyntheticClip.temporaryURL("missing"), pageWasSeenLive: false)
        if case .unchecked = verdict {} else { Issue.record("expected .unchecked, got \(verdict)") }
    }

    @Test func anUnreadableClipIsNeverAttachedEvenOnAPageSeenLive() async {
        let server = FakePopServer()
        await server.setModerateHandler { _ in ModerateResponse(flagged: false, categories: []) }
        let verdict = await FrameTripwire(server: server)
            .checkClip(at: SyntheticClip.temporaryURL("missing"), pageWasSeenLive: true)
        if case .unchecked = verdict {} else { Issue.record("expected .unchecked, got \(verdict)") }
    }
}

actor InFlightCounter {
    private var current = 0
    private(set) var peak = 0

    func enter() {
        current += 1
        peak = max(peak, current)
    }

    func leave() { current -= 1 }
}
