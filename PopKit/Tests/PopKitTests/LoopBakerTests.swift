import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import PopKit

@Suite struct LoopBakerTests {
    private static let sourceSeconds = 4.0
    private static let fps: Int32 = 30

    @available(macOS 26.0, iOS 26.0, *)
    @Test func bakesASeamlessLoopOneCrossfadeShorterThanTheSource() async throws {
        let source = SyntheticClip.temporaryURL("bake-source")
        let baked = SyntheticClip.temporaryURL("bake-out")
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: baked)
        }
        try await SyntheticClip.write(to: source, seconds: Self.sourceSeconds, fps: Self.fps)

        let loopSeconds = try await LoopBaker.bake(source, to: baked)

        // (1) One crossfade shorter than the source, give or take a frame.
        let frameSeconds = 1 / Double(Self.fps)
        let expected = Self.sourceSeconds - LoopBaker.crossfadeSeconds
        #expect(abs(loopSeconds - expected) <= frameSeconds + 0.001)
        let asset = AVURLAsset(url: baked)
        let fileSeconds = try await asset.load(.duration).seconds
        #expect(abs(fileSeconds - expected) <= frameSeconds + 0.001)

        // (2) H.264, no wider than maxWidth, even dimensions, no audio.
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let (size, formats) = try await track.load(.naturalSize, .formatDescriptions)
        #expect(Int(size.width) <= LoopBaker.maxWidth && Int(size.width).isMultiple(of: 2))
        #expect(Int(size.height).isMultiple(of: 2))
        #expect(formats.first.map(CMFormatDescriptionGetMediaSubType) == kCMVideoCodecType_H264)
        #expect(try await asset.loadTracks(withMediaType: .audio).isEmpty)

        // (3) The last frame runs into the first about as smoothly as any frame into the next.
        let bakedFrames = try await FrameDiff.frames(of: baked)
        let steps = FrameDiff.consecutiveDifferences(bakedFrames)
        let median = FrameDiff.median(steps)
        let boundary = FrameDiff.boundaryDifference(bakedFrames)
        let bound = 1.5 * median
        let largestStep = steps.max() ?? 0
        print("LoopBaker boundary diff \(boundary) vs consecutive median \(median) (bound \(bound)), largest step \(largestStep)")
        #expect(median > 1, "the synthetic clip should move")
        #expect(boundary <= bound)
        #expect(largestStep <= 2 * bound, "the crossfade blends rather than cutting")

        // (4) Control: the raw source jumps at its loop point.
        let sourceBoundary = FrameDiff.boundaryDifference(try await FrameDiff.frames(of: source))
        print("LoopBaker source boundary diff \(sourceBoundary)")
        #expect(sourceBoundary > 2 * bound)
    }

    @available(macOS 26.0, iOS 26.0, *)
    @Test func overwritesAnExistingDestination() async throws {
        let source = SyntheticClip.temporaryURL("bake-source")
        let baked = SyntheticClip.temporaryURL("bake-out")
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: baked)
        }
        try await SyntheticClip.write(to: source, seconds: 2.5, fps: 15, width: 160, height: 96)
        try Data("stale".utf8).write(to: baked)
        let loopSeconds = try await LoopBaker.bake(source, to: baked)
        #expect(abs(loopSeconds - 1.7) < 0.1)
        #expect(try await AVURLAsset(url: baked).load(.duration).seconds > 1.5)
    }

    @available(macOS 26.0, iOS 26.0, *)
    @Test func rejectsAClipShorterThanThreeCrossfades() async throws {
        let source = SyntheticClip.temporaryURL("bake-short")
        defer { try? FileManager.default.removeItem(at: source) }
        try await SyntheticClip.write(to: source, seconds: 2, fps: 15, width: 160, height: 96)
        await #expect(throws: LoopBaker.BakeError.tooShort) {
            try await LoopBaker.bake(source, to: SyntheticClip.temporaryURL("never"))
        }
    }

    @available(macOS 26.0, iOS 26.0, *)
    @Test func rejectsAFileWithoutVideo() async {
        await #expect(throws: LoopBaker.BakeError.self) {
            try await LoopBaker.bake(SyntheticClip.temporaryURL("missing"), to: SyntheticClip.temporaryURL("never"))
        }
    }

    @available(macOS 26.0, iOS 26.0, *)
    @Test func rendersNoWiderThanMaxWidthWithEvenSides() {
        #expect(LoopBaker.renderSize(naturalSize: CGSize(width: 832, height: 480), transform: .identity)
            == CGSize(width: 832, height: 480))
        #expect(LoopBaker.renderSize(naturalSize: CGSize(width: 1000, height: 600), transform: .identity)
            == CGSize(width: 832, height: 500))
        #expect(LoopBaker.renderSize(naturalSize: CGSize(width: 321, height: 191), transform: .identity)
            == CGSize(width: 322, height: 192))
    }

    @available(macOS 26.0, iOS 26.0, *)
    @Test func rendersARotatedSourceUpright() {
        let rotated = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 480, ty: 0)
        #expect(LoopBaker.renderSize(naturalSize: CGSize(width: 832, height: 480), transform: rotated)
            == CGSize(width: 480, height: 832))
    }

    @available(macOS 26.0, iOS 26.0, *)
    @Test func frameDurationFollowsTheSourceFrameRate() {
        #expect(LoopBaker.frameDuration(nominalFrameRate: 30) == CMTime(value: 1, timescale: 30))
        #expect(LoopBaker.frameDuration(nominalFrameRate: 24) == CMTime(value: 1, timescale: 24))
        #expect(LoopBaker.frameDuration(nominalFrameRate: 29.97) == CMTime(value: 1, timescale: 30))
        #expect(LoopBaker.frameDuration(nominalFrameRate: 0) == CMTime(value: 1, timescale: 30))
        #expect(LoopBaker.frameDuration(nominalFrameRate: .nan) == CMTime(value: 1, timescale: 30))
    }
}
