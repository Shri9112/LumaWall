import AppKit
import AVFoundation

/// The backing content view for a WallpaperWindow, hosting the hardware-accelerated AVPlayerLayer.
public final class WallpaperContentView: NSView {
    public var playerLayer: AVPlayerLayer? {
        didSet {
            oldValue?.removeFromSuperlayer()
            if let playerLayer {
                layer?.addSublayer(playerLayer)
                playerLayer.frame = bounds
            }
        }
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayer()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
    }

    private func setupLayer() {
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
    }

    public override func layout() {
        super.layout()
        // Disable CoreAnimation implicit action during layout to prevent stretching artifacts
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer?.frame = bounds
        CATransaction.commit()
    }
}
