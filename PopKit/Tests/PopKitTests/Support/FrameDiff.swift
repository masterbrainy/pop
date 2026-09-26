import AVFoundation
import CoreVideo
import Foundation

/// Reads every frame of a video file and compares frames by mean absolute pixel difference.
enum FrameDiff {
    struct ReadError: Error, CustomStringConvertible {
        let description: String
    }

    /// Every second pixel on every second row, as B, G, R bytes.
    typealias Frame = [UInt8]

    static func frames(of url: URL) async throws -> [Frame] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ReadError(description: "no video track in \(url.lastPathComponent)")
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        reader.add(output)
        guard reader.startReading() else { throw ReadError(description: "startReading: \(String(describing: reader.error))") }
        var frames: [Frame] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            frames.append(downsample(buffer))
        }
        guard reader.status == .completed else { throw ReadError(description: "read: \(String(describing: reader.error))") }
        return frames
    }

    static func meanAbsoluteDifference(_ a: Frame, _ b: Frame) -> Double {
        precondition(a.count == b.count && !a.isEmpty, "frames differ in size")
        let total = zip(a, b).reduce(0) { sum, pair in sum + abs(Int(pair.0) - Int(pair.1)) }
        return Double(total) / Double(a.count)
    }

    /// The difference between each frame and the next.
    static func consecutiveDifferences(_ frames: [Frame]) -> [Double] {
        zip(frames, frames.dropFirst()).map { meanAbsoluteDifference($0, $1) }
    }

    /// The difference across the loop point: the last frame against the first.
    static func boundaryDifference(_ frames: [Frame]) -> Double {
        guard let first = frames.first, let last = frames.last else { return 0 }
        return meanAbsoluteDifference(last, first)
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    private static func downsample(_ buffer: CVPixelBuffer) -> Frame {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return [] }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        var frame: Frame = []
        frame.reserveCapacity((width / 2 + 1) * (height / 2 + 1) * 3)
        for y in stride(from: 0, to: height, by: 2) {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
            for x in stride(from: 0, to: width, by: 2) {
                let pixel = row.advanced(by: x * 4)
                frame.append(pixel[0])
                frame.append(pixel[1])
                frame.append(pixel[2])
            }
        }
        return frame
    }
}
