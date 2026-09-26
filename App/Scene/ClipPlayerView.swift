import AVFoundation
import SwiftUI

/// Plays a saved page's recorded clip on a seamless loop (`ClipReplayScene`): no network,
/// no Reactor session, so a finished book replays exactly as it was made (PRD P-01).
struct ClipPlayerView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.play(url)
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        if view.currentURL != url { view.play(url) }
    }

    static func dismantleUIView(_ view: PlayerView, coordinator: ()) {
        view.stop()
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }

        private var looper: AVPlayerLooper?
        private let player = AVQueuePlayer()
        private(set) var currentURL: URL?

        override init(frame: CGRect) {
            super.init(frame: frame)
            let playerLayer = layer as! AVPlayerLayer
            playerLayer.player = player
            playerLayer.videoGravity = .resizeAspectFill
            player.isMuted = true
            backgroundColor = .clear
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        func play(_ url: URL) {
            currentURL = url
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            player.play()
        }

        func stop() {
            player.pause()
            looper = nil
        }
    }
}
