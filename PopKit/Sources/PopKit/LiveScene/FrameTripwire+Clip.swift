import AVFoundation
import Foundation

/// Clip moderation: before a recorded clip is attached to its page, frames spread across the
/// whole clip go through the same image moderation as the live frames.
extension FrameTripwire {
    /// How far in from each end of the clip the first and last samples sit, in seconds.
    static let clipEdgeSeconds = 0.5

    /// When to sample a clip of `duration` seconds: half a second in, half a second before
    /// the end, and evenly between them no more than `clipCheckSpacing` apart. A 10 s clip
    /// gives [0.5, 3.5, 6.5, 9.5]. A clip under a second is sampled once, in the middle.
    public static func clipSampleTimes(duration: Double) -> [Double] {
        guard duration.isFinite, duration > 0 else { return [] }
        let first = min(clipEdgeSeconds, duration / 2)
        let last = max(first, duration - clipEdgeSeconds)
        let spacing = Double(clipCheckSpacing.components.seconds)
        let gaps = max(1, Int(((last - first) / spacing).rounded(.up)))
        let times = (0...gaps).map { index in
            let time = first + (last - first) * Double(index) / Double(gaps)
            return (time * 1000).rounded() / 1000
        }
        return times.reduce(into: [Double]()) { unique, time in
            if time >= 0, time < duration, unique.last != time { unique.append(time) }
        }
    }

    /// Samples the clip at `url`, checks every sampled frame at once, and decides whether the
    /// clip may be attached. A clip that can't be read counts as an unchecked frame, so a page
    /// nobody has seen fails closed.
    public func checkClip(at url: URL, pageWasSeenLive: Bool) async -> ClipVerdict {
        let verdicts: [Verdict]
        do {
            let duration = try await AVURLAsset(url: url).load(.duration).seconds
            let frames = try await ClipFrameSampler.frames(
                from: url, at: Self.clipSampleTimes(duration: duration), maxSide: Self.maxSide
            )
            verdicts = await checkAll(frames)
        } catch {
            verdicts = [.unchecked("clip unreadable: \(error)")]
        }
        return ClipVerdict.decide(verdicts, pageWasSeenLive: pageWasSeenLive)
    }

    /// Checks every frame in parallel and returns the verdicts in frame order.
    private func checkAll(_ frames: [(base64: String, mimeType: String)]) async -> [Verdict] {
        await withTaskGroup(of: (Int, Verdict).self) { group in
            for (index, frame) in frames.enumerated() {
                group.addTask { (index, await check(base64: frame.base64, mimeType: frame.mimeType)) }
            }
            var verdicts: [(Int, Verdict)] = []
            for await result in group { verdicts.append(result) }
            return verdicts.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }
}
