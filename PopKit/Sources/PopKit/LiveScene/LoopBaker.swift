import AVFoundation
import CoreGraphics
import Foundation

/// Bakes a page's recorded clip into a loop with no visible jump where it wraps around.
///
/// For a source of `D` seconds and a crossfade of `c`, the loop is `D − c` long. It plays the
/// source from `c` to the end, and over its last `c` seconds the source's opening `c` seconds
/// fade in on top. The final frame is then the source just before `c`, which runs straight
/// into the loop's first frame, the source at `c`. No audio is kept.
///
/// Uses the iOS 26 / macOS 26 video composition API; the app itself targets iOS 27.1.
@available(macOS 26.0, iOS 26.0, *)
public enum LoopBaker {
    public enum BakeError: Error, Equatable {
        /// The source is shorter than three crossfades, too short to loop smoothly.
        case tooShort
        /// The source can't be read or has no video.
        case noVideoTrack
        case exportFailed(String)
    }

    public static let crossfadeSeconds = 0.8
    /// The widest loop we write; wider sources are scaled down.
    public static let maxWidth = 832
    static let fallbackFrameRate: Int32 = 30
    static let maxFrameRate: Int32 = 60

    /// Writes the loop of `source` to `destination` as an H.264 mp4, replacing any file
    /// already there, and returns the loop's length in seconds.
    public static func bake(_ source: URL, to destination: URL) async throws -> Double {
        // The asset must outlive its track: a track only weakly holds its asset.
        let asset = AVURLAsset(url: source)
        let track = try await videoTrack(of: asset)
        let (naturalSize, transform, frameRate, sourceRange) = try await loadProperties(of: track)
        guard sourceRange.duration.seconds >= 3 * crossfadeSeconds else { throw BakeError.tooShort }

        let composition = AVMutableComposition()
        let (main, head) = try addTracks(to: composition, from: track, range: sourceRange)
        let size = renderSize(naturalSize: naturalSize, transform: transform)
        let video = videoComposition(
            main: main, head: head,
            loopLength: composition.duration,
            frameDuration: frameDuration(nominalFrameRate: frameRate),
            renderSize: size,
            layerTransform: fittingTransform(naturalSize: naturalSize, transform: transform, renderSize: size)
        )
        try await export(composition, video: video, to: destination)
        return withExtendedLifetime(asset) { composition.duration.seconds }
    }

    /// The loop's size: the source upright, scaled down to at most `maxWidth` wide, with
    /// both sides rounded to even numbers for the encoder.
    static func renderSize(naturalSize: CGSize, transform: CGAffineTransform) -> CGSize {
        let upright = CGRect(origin: .zero, size: naturalSize).applying(transform).standardized
        guard upright.width > 0, upright.height > 0 else { return CGSize(width: 2, height: 2) }
        let scale = min(1, CGFloat(maxWidth) / upright.width)
        return CGSize(width: even(upright.width * scale), height: even(upright.height * scale))
    }

    /// One frame at the source's frame rate, rounded to a whole number of frames per second.
    /// An unknown or unlikely rate (MediaRecorder files sometimes report one) falls back to 30.
    static func frameDuration(nominalFrameRate: Float) -> CMTime {
        guard nominalFrameRate.isFinite, nominalFrameRate >= 1 else {
            return CMTime(value: 1, timescale: fallbackFrameRate)
        }
        let rate = min(maxFrameRate, Int32(nominalFrameRate.rounded()))
        return CMTime(value: 1, timescale: rate)
    }

    private static func even(_ length: CGFloat) -> CGFloat {
        max(2, (length / 2).rounded() * 2)
    }

    /// Maps the source's pixels onto the render canvas: upright, moved to the origin, scaled.
    private static func fittingTransform(naturalSize: CGSize, transform: CGAffineTransform, renderSize: CGSize)
        -> CGAffineTransform {
        let upright = CGRect(origin: .zero, size: naturalSize).applying(transform).standardized
        guard upright.width > 0, upright.height > 0 else { return transform }
        return transform
            .concatenating(CGAffineTransform(translationX: -upright.minX, y: -upright.minY))
            .concatenating(CGAffineTransform(
                scaleX: renderSize.width / upright.width, y: renderSize.height / upright.height
            ))
    }

    private static func videoTrack(of asset: AVURLAsset) async throws -> AVAssetTrack {
        let tracks: [AVAssetTrack]
        do {
            tracks = try await asset.loadTracks(withMediaType: .video)
        } catch {
            throw BakeError.noVideoTrack
        }
        guard let track = tracks.first else { throw BakeError.noVideoTrack }
        return track
    }

    private static func loadProperties(of track: AVAssetTrack) async throws
        -> (CGSize, CGAffineTransform, Float, CMTimeRange) {
        do {
            return try await track.load(.naturalSize, .preferredTransform, .nominalFrameRate, .timeRange)
        } catch {
            throw BakeError.noVideoTrack
        }
    }

    /// Track 1 (`main`) holds the source from `c` to the end, starting at 0. Track 2 (`head`)
    /// holds the source's first `c` seconds, placed over the loop's last `c` seconds.
    private static func addTracks(to composition: AVMutableComposition, from track: AVAssetTrack, range: CMTimeRange)
        throws -> (main: AVMutableCompositionTrack, head: AVMutableCompositionTrack) {
        guard let main = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let head = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw BakeError.exportFailed("couldn't add composition tracks") }
        let crossfade = CMTime(seconds: crossfadeSeconds, preferredTimescale: 600)
        let loopLength = range.duration - crossfade
        do {
            try main.insertTimeRange(
                CMTimeRange(start: range.start + crossfade, duration: loopLength), of: track, at: .zero
            )
            try head.insertTimeRange(
                CMTimeRange(start: range.start, duration: crossfade), of: track, at: loopLength - crossfade
            )
        } catch {
            throw BakeError.exportFailed("couldn't build the loop: \(error)")
        }
        return (main, head)
    }

    /// Only `main` shows until the crossfade; then `head` fades in over it. The fade reaches
    /// full opacity one frame early, so the last frame is purely the source just before `c`.
    private static func videoComposition(
        main: AVMutableCompositionTrack, head: AVMutableCompositionTrack,
        loopLength: CMTime, frameDuration: CMTime, renderSize: CGSize, layerTransform: CGAffineTransform
    ) -> AVVideoComposition {
        let crossfade = CMTime(seconds: crossfadeSeconds, preferredTimescale: 600)
        let fadeStart = loopLength - crossfade

        var mainLayer = AVVideoCompositionLayerInstruction.Configuration(assetTrack: main)
        mainLayer.setTransform(layerTransform, at: .zero)
        var headLayer = AVVideoCompositionLayerInstruction.Configuration(assetTrack: head)
        headLayer.setTransform(layerTransform, at: .zero)
        headLayer.addOpacityRamp(AVVideoCompositionLayerInstruction.OpacityRamp(
            timeRange: CMTimeRange(start: fadeStart, duration: crossfade - frameDuration), start: 0, end: 1
        ))
        let mainOnly = AVVideoCompositionLayerInstruction(configuration: mainLayer)
        let headOver = AVVideoCompositionLayerInstruction(configuration: headLayer)

        let steady = AVVideoCompositionInstruction(configuration: .init(
            layerInstructions: [mainOnly], timeRange: CMTimeRange(start: .zero, end: fadeStart)
        ))
        let fade = AVVideoCompositionInstruction(configuration: .init(
            layerInstructions: [headOver, mainOnly], timeRange: CMTimeRange(start: fadeStart, end: loopLength)
        ))
        return AVVideoComposition(configuration: .init(
            frameDuration: frameDuration, instructions: [steady, fade], renderSize: renderSize
        ))
    }

    private static func export(_ composition: AVComposition, video: AVVideoComposition, to destination: URL) async throws {
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw BakeError.exportFailed("no export session")
        }
        session.videoComposition = video
        session.shouldOptimizeForNetworkUse = false
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try await session.export(to: destination, as: .mp4)
        } catch {
            throw BakeError.exportFailed(String(describing: error))
        }
    }
}
