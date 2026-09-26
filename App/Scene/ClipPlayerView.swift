import AVFoundation
import SwiftUI

/// Plays a page's baked loop on repeat: no network, no Reactor session, so a finished book
/// replays exactly as it was made (PRD P-01), and while creating, a page whose loop is ready
/// plays it instead of keeping the live session. `onReady` fires once the first frame of this
/// clip can be displayed, so the live video can crossfade to it without a flash of the still.
struct ClipPlayerView: UIViewRepresentable {
    let url: URL
    var onReady: @MainActor () -> Void = {}

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.onReady = onReady
        view.play(url)
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        view.onReady = onReady
        if view.currentURL != url { view.play(url) }
    }

    static func dismantleUIView(_ view: PlayerView, coordinator: ()) {
        view.stop()
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }

        var onReady: @MainActor () -> Void = {}
        private var looper: AVPlayerLooper?
        private let player = AVQueuePlayer()
        private var readyObservation: NSKeyValueObservation?
        private(set) var currentURL: URL?

        private var playerLayer: AVPlayerLayer? { layer as? AVPlayerLayer }

        override init(frame: CGRect) {
            super.init(frame: frame)
            playerLayer?.player = player
            playerLayer?.videoGravity = .resizeAspectFill
            player.isMuted = true
            backgroundColor = .clear
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        func play(_ url: URL) {
            currentURL = url
            let item = AVPlayerItem(asset: ClipPreloader.shared.asset(for: url))
            looper = AVPlayerLooper(player: player, templateItem: item)
            watchReadiness()
            player.play()
        }

        func stop() {
            readyObservation = nil
            player.pause()
            looper = nil
        }

        /// Reports `onReady` once per clip, when the layer can show its first frame.
        private func watchReadiness() {
            readyObservation = nil
            guard let playerLayer else { return }
            if playerLayer.isReadyForDisplay {
                onReady()
                return
            }
            readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] layer, _ in
                guard layer.isReadyForDisplay else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.readyObservation != nil else { return }
                    self.readyObservation = nil
                    self.onReady()
                }
            }
        }
    }
}

/// Warms the page behind's loop before the fold (its asset loads its tracks and duration),
/// so when the page opens its loop shows at once. Keeps only the few most recent clips.
@MainActor
final class ClipPreloader {
    static let shared = ClipPreloader()
    private static let capacity = 4

    private var assets: [URL: AVURLAsset] = [:]
    private var order: [URL] = []

    /// The warmed asset for `url`, or a fresh one.
    func asset(for url: URL) -> AVURLAsset {
        assets[url] ?? AVURLAsset(url: url)
    }

    /// Starts loading `url` so a player made for it later is ready sooner.
    func warm(_ url: URL) {
        guard assets[url] == nil else { return }
        let asset = AVURLAsset(url: url)
        assets[url] = asset
        order.append(url)
        if order.count > Self.capacity {
            let oldest = order.removeFirst()
            assets[oldest] = nil
        }
        Task {
            _ = try? await asset.load(.tracks, .duration, .isPlayable)
        }
    }
}
