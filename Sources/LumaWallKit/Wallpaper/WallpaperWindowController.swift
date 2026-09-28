import AppKit
import Foundation

/// Manages the lifecycle of a WallpaperWindow and its associated video player on a given screen.
@MainActor
public final class WallpaperWindowController: NSWindowController {
    public let targetScreen: NSScreen
    public let player: WallpaperPlayer
    private let contentView: WallpaperContentView

    public init(screen: NSScreen, isMuted: Bool = true) {
        self.targetScreen = screen
        self.player = WallpaperPlayer(isMuted: isMuted)
        self.contentView = WallpaperContentView(frame: screen.frame)

        let window = WallpaperWindow(screen: screen)
        window.contentView = contentView

        super.init(window: window)

        // Connect player's layer to content view
        contentView.playerLayer = player.playerLayer
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Loads and begins playback of a video file on this desktop window
    public func loadVideo(url: URL) {
        player.loadVideo(url: url, autoPlay: true)
        showWallpaper()
    }

    /// Displays the desktop wallpaper window behind desktop icons
    public func showWallpaper() {
        guard let window = self.window else { return }
        window.setFrame(targetScreen.frame, display: true)
        window.orderFrontRegardless()
        player.play()
        LumaLogger.display.info("Showing wallpaper window on screen: \(self.targetScreen.localizedName)")
    }

    /// Hides the desktop wallpaper window and pauses playback
    public func hideWallpaper() {
        player.pause()
        window?.orderOut(nil)
        LumaLogger.display.info("Hiding wallpaper window on screen: \(self.targetScreen.localizedName)")
    }

    /// Updates the frame when screen resolution or bounds change
    public func updateFrame(for screen: NSScreen) {
        guard let window = self.window else { return }
        window.setFrame(screen.frame, display: true)
        contentView.needsLayout = true
        LumaLogger.display.info("Updated wallpaper frame for screen: \(screen.localizedName) to \(screen.frame.debugDescription)")
    }

    /// Fully stops playback and clears window resources
    public func cleanup() {
        player.stop()
        contentView.playerLayer = nil
        window?.orderOut(nil)
        self.window = nil
    }
}
