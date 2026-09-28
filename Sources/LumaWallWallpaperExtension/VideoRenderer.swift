import Foundation
import AVFoundation
import QuartzCore
import AppKit

public final class ExtensionVideoRenderer: @unchecked Sendable {
    private let playerLayer: AVPlayerLayer
    private var queuePlayer: AVQueuePlayer?
    private var looper: AVPlayerLooper?

    public init(rootLayer: CALayer, videoURL: URL, thumbnailURL: URL?) {
        // 1. Establish background still image to prevent black flash
        if let thumbnailURL,
           let image = NSImage(contentsOf: thumbnailURL),
           let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            rootLayer.contents = cgImage
            rootLayer.contentsGravity = .resizeAspectFill
        }

        // 2. Hardware-accelerated AVPlayerLayer
        let playerItem = AVPlayerItem(url: videoURL)
        let player = AVQueuePlayer(playerItem: playerItem)
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false

        self.looper = AVPlayerLooper(player: player, templateItem: playerItem)
        self.queuePlayer = player

        let layer = AVPlayerLayer(player: player)
        layer.frame = rootLayer.bounds
        layer.videoGravity = .resizeAspectFill
        layer.contentsScale = rootLayer.contentsScale

        rootLayer.addSublayer(layer)
        self.playerLayer = layer

        player.play()
    }

    public func pause() {
        queuePlayer?.pause()
    }

    public func resume() {
        queuePlayer?.play()
    }

    public func cleanup() {
        queuePlayer?.pause()
        queuePlayer?.removeAllItems()
        looper?.disableLooping()
        looper = nil
        queuePlayer = nil
        playerLayer.removeFromSuperlayer()
    }
}
