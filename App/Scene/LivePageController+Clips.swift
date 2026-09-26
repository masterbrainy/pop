import Foundation
import PopKit

/// Recording, checking and baking each page's loop, and the live frame tripwire.
extension LivePageController {
    /// Records the flow's next `clipSeconds` (hidden or not). A newer flow cancels the
    /// recording, and the page refuses to record once it's been superseded.
    func recordClip(_ flow: Flow) {
        recordTask?.cancel()
        // The live tripwire covers the clip only if it watched this page for the whole recording.
        recordingWatch = (flow.generation, liveKey == flow.key)
        recordTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await bridge.startClip(maxSeconds: Self.clipSeconds, generation: flow.generation)
                try await Task.sleep(for: .seconds(Self.clipSeconds))
                let clip = try await bridge.stopClip()
                guard self.flow?.generation == flow.generation else {
                    Self.remove(clip.url)
                    return
                }
                let watched = recordingWatch?.generation == flow.generation && recordingWatch?.watched == true
                recordTask = nil
                process(clip.url, for: flow.key, index: flow.index, seenLive: watched)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                AppLog.scene.error("clip failed: \(error.localizedDescription, privacy: .public)")
                log("p\(flow.index + 1) clip failed: \(error.localizedDescription)")
                recordTask = nil
                loopFailed(flow.key, index: flow.index)
            }
        }
    }

    /// The live page stopped being watched (turned away, handed over): its recording now isn't.
    func recordingUnwatched(_ key: PageKey) {
        guard let watch = recordingWatch, flow?.key == key, flow?.generation == watch.generation else { return }
        recordingWatch = (watch.generation, false)
    }

    /// Whether this page's loop is still being recorded or checked and baked.
    func isMakingLoop(for key: PageKey) -> Bool {
        (flow?.key == key && recordTask != nil) || processTasks[key] != nil
    }

    /// Checks the recorded clip's frames, bakes it into a seamless loop and hands it over.
    /// Runs on its own (a turn doesn't stop it): the loop still belongs to its page version.
    func process(_ raw: URL, for key: PageKey, index: Int, seenLive: Bool) {
        processTasks[key]?.cancel()
        processTasks[key] = Task { [weak self] in
            guard let self else { return }
            defer { if !Task.isCancelled { self.processTasks[key] = nil } }
            guard let tripwire else {
                Self.remove(raw)
                return
            }
            let verdict = await tripwire.checkClip(at: raw, pageWasSeenLive: seenLive)
            guard !Task.isCancelled, !held.contains(key) else {
                Self.remove(raw)
                return
            }
            switch verdict {
            case .attach:
                let loop = await bake(raw, page: index)
                // Flagged (or replaced) while baking: the loop is never shown.
                guard !Task.isCancelled, !held.contains(key) else {
                    Self.remove(loop)
                    return
                }
                onClip(key, loop)
            case let .flagged(categories):
                Self.remove(raw)
                AppLog.scene.error("clip flagged on page \(index + 1): \(categories.joined(separator: ","), privacy: .public)")
                log("p\(index + 1) clip flagged: \(categories.joined(separator: ","))")
                hold(key, index: index)
            case let .unchecked(reason):
                Self.remove(raw)
                log("p\(index + 1) clip not attached (unchecked: \(reason))")
                loopFailed(key, index: index)
            }
        }
    }

    /// No loop came of this recording. If the flow still runs, it records once more; after
    /// that the page is spent (it keeps its still) and the session moves on, so a page that
    /// can't give a loop never holds the paid session for good.
    private func loopFailed(_ key: PageKey, index: Int) {
        if let current = flow, current.key == key, current.hasFirstFrame, !loopRetried.contains(key) {
            loopRetried.insert(key)
            log("p\(index + 1) recording again")
            recordClip(current)
            return
        }
        spent.insert(key)
        if flow?.key == key {
            endFlow()
            flow = nil
        }
        replan()
    }

    /// The baked loop, or the raw clip (which loops with a seam) if baking fails.
    private func bake(_ raw: URL, page index: Int) async -> URL {
        let destination = raw.deletingLastPathComponent().appending(path: "\(UUID().uuidString)-loop.mp4")
        let started = ContinuousClock.now
        do {
            let seconds = try await LoopBaker.bake(raw, to: destination)
            Self.remove(raw)
            let ms = Int((ContinuousClock.now - started) / .milliseconds(1))
            log("p\(index + 1) loop baked: \(String(format: "%.1f", seconds)) s in \(ms) ms")
            return destination
        } catch {
            AppLog.scene.error("loop bake failed: \(error.localizedDescription, privacy: .public)")
            log("p\(index + 1) loop bake failed, keeping the raw clip: \(error.localizedDescription)")
            Self.remove(destination)
            return raw
        }
    }

    /// A flagged frame or clip: stop the video, drop any loop in the making, and keep the
    /// page's still for good.
    func hold(_ key: PageKey, index: Int) {
        framesFlagged += 1
        held.insert(key)
        processTasks[key]?.cancel()
        processTasks[key] = nil
        if flow?.key == key {
            endFlow()
            flow = nil
            Task { try? await bridge.pause() }
        }
        onFrameFlagged(key)
        replan()
    }

    /// While a page shows live, samples frames through moderation (`FrameTripwire`).
    func watchFrames(on key: PageKey) {
        tripwireTask?.cancel()
        guard let tripwire, let index = onScreen?.page.index else { return }
        tripwireTask = Task { [weak self] in
            var check = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: FrameTripwire.delay(beforeCheck: check))
                check += 1
                guard let self, !Task.isCancelled, self.liveKey == key else { return }
                guard let frame = try? await self.bridge.sampleFrame(maxSide: FrameTripwire.maxSide) else { continue }
                let verdict = await tripwire.check(base64: frame.base64, mimeType: frame.mimeType)
                guard self.liveKey == key else { return }
                self.framesChecked += 1
                switch verdict {
                case .clear:
                    break
                case let .unchecked(reason):
                    AppLog.scene.error("frame check failed: \(reason, privacy: .public)")
                case let .flagged(categories):
                    AppLog.scene.error("frame flagged on page \(index + 1): \(categories.joined(separator: ","), privacy: .public)")
                    self.hold(key, index: index)
                    return
                }
            }
        }
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
