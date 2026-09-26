import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Pulls still frames out of a recorded page clip as base64 JPEGs, ready for image moderation.
public enum ClipFrameSampler {
    public enum SampleError: Error, Equatable {
        case noVideoTrack
    }

    /// How far from the asked-for time a frame may come from, in seconds.
    static let tolerance = 0.1
    static let jpegQuality = 0.7

    /// One JPEG per time in `seconds` whose long side is at most `maxSide`. A time that can't
    /// be read (past the end, a decode error) is skipped rather than failing the others.
    /// Throws when the file can't be opened or has no video.
    public static func frames(from url: URL, at seconds: [Double], maxSide: Int) async throws
        -> [(base64: String, mimeType: String)] {
        let asset = AVURLAsset(url: url)
        guard try await !asset.loadTracks(withMediaType: .video).isEmpty else { throw SampleError.noVideoTrack }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let tolerance = CMTime(seconds: tolerance, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        generator.maximumSize = CGSize(width: maxSide, height: maxSide)

        var frames: [(base64: String, mimeType: String)] = []
        for second in seconds {
            guard let image = try? await generator.image(at: CMTime(seconds: second, preferredTimescale: 600)).image,
                  let jpeg = jpegData(image)
            else { continue }
            frames.append((base64: jpeg.base64EncodedString(), mimeType: "image/jpeg"))
        }
        return frames
    }

    static func jpegData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        let options = [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
