import AVFoundation
import CoreVideo
import Foundation

/// Writes a small H.264 mp4 for clip tests: a textured pattern that slides sideways at a
/// steady speed, so consecutive frames differ a little while frames far apart differ a lot.
enum SyntheticClip {
    struct WriteError: Error, CustomStringConvertible {
        let description: String
    }

    /// Pixels the pattern moves per frame.
    static let pixelsPerFrame = 2

    static func temporaryURL(_ name: String = "clip") -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "popkit-\(name)-\(UUID().uuidString).mp4")
    }

    static func write(to url: URL, seconds: Double, fps: Int32 = 30, width: Int = 320, height: Int = 192) async throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 4_000_000],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        guard writer.canAdd(input) else { throw WriteError(description: "can't add video input") }
        writer.add(input)
        guard writer.startWriting() else { throw WriteError(description: "startWriting: \(String(describing: writer.error))") }
        writer.startSession(atSourceTime: .zero)

        let frameCount = Int((seconds * Double(fps)).rounded())
        let pattern = texture(length: width + frameCount * pixelsPerFrame + 64)
        for index in 0..<frameCount {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(1)) }
            let buffer = try makeFrame(index: index, width: width, height: height, pattern: pattern, adaptor: adaptor)
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: fps)) else {
                throw WriteError(description: "append frame \(index): \(String(describing: writer.error))")
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw WriteError(description: "finish: \(String(describing: writer.error))") }
    }

    /// A non-repeating 1D texture: three sines with unrelated wavelengths.
    private static func texture(length: Int) -> [UInt8] {
        (0..<length).map { x in
            let x = Double(x)
            let value = 128 + 40 * sin(x / 23 * 2 * .pi) + 35 * sin(x / 37 * 2 * .pi) + 30 * sin(x / 61 * 2 * .pi)
            return UInt8(max(0, min(255, value.rounded())))
        }
    }

    private static func makeFrame(
        index: Int, width: Int, height: Int, pattern: [UInt8], adaptor: AVAssetWriterInputPixelBufferAdaptor
    ) throws -> CVPixelBuffer {
        guard let pool = adaptor.pixelBufferPool else { throw WriteError(description: "no pixel buffer pool") }
        var made: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made)
        guard let buffer = made else { throw WriteError(description: "no pixel buffer") }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw WriteError(description: "no base address") }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let shift = index * pixelsPerFrame
        for y in 0..<height {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
            let blue = UInt8(40 + (y * 160) / max(1, height - 1))
            for x in 0..<width {
                let pixel = row.advanced(by: x * 4)
                pixel[0] = blue
                pixel[1] = pattern[x + shift + 29]
                pixel[2] = pattern[x + shift]
                pixel[3] = 255
            }
        }
        return buffer
    }
}
