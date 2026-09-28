import AppKit
import CoreGraphics

/// A borderless, non-interactive, full-screen NSWindow positioned at the desktop layer
/// strictly behind Finder desktop icons and regular application windows.
public final class WallpaperWindow: NSWindow {

    public init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        configureDesktopProperties(for: screen)
    }

    private func configureDesktopProperties(for screen: NSScreen) {
        // 1. Position window at the desktop level (-2147483623)
        // Desktop Icon window is at -2147483603 (20 units higher), ensuring
        // this window is rendered strictly behind all desktop files/icons.
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))

        // 2. Non-interactive pass-through for all mouse events
        self.ignoresMouseEvents = true
        self.acceptsMouseMovedEvents = false

        // 3. Prevent shadows and visual artifacts
        self.hasShadow = false
        self.isOpaque = true
        self.backgroundColor = .black

        // 4. Spaces and Mission Control collection behavior:
        // - .canJoinAllSpaces: Stays visible across all Spaces/desktops
        // - .stationary: Does not move/tile during Mission Control / Exposé
        // - .ignoresCycle: Excluded from Cmd+Tab / window cycling
        // - .fullScreenAuxiliary: Stays visible behind fullscreen applications
        self.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]

        // 5. Anchor to screen frame
        self.setFrame(screen.frame, display: true)
    }

    // Window must NEVER steal key focus or main status from active applications
    public override var canBecomeKey: Bool {
        return false
    }

    public override var canBecomeMain: Bool {
        return false
    }
}
