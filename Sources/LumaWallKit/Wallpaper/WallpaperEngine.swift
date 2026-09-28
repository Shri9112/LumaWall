import AppKit
import Foundation
import Observation

/// The central coordinator managing desktop wallpaper playback across physical displays.
@Observable
@MainActor
public final class WallpaperEngine {
    public static let shared = WallpaperEngine()

    public private(set) var activeWallpaperURL: URL?
    public private(set) var isDesktopActive: Bool = false
    public private(set) var isPlaying: Bool = false
    public private(set) var isMuted: Bool = true

    private var windowControllers: [WallpaperWindowController] = []
    private var screenChangeObserver: (any NSObjectProtocol)?

    public init() {
        setupScreenChangeObserver()
    }

    // MARK: - Public Engine Controls

    /// Sets the specified video file as the live desktop wallpaper on all connected displays.
    public func setWallpaper(url: URL) {
        LumaLogger.app.info("Setting desktop wallpaper: \(url.lastPathComponent)")

        // Stop any currently running desktop wallpaper
        stopWallpaper()

        self.activeWallpaperURL = url
        self.isDesktopActive = true
        self.isPlaying = true

        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            LumaLogger.display.error("No active NSScreen found")
            return
        }

        for screen in screens {
            let controller = WallpaperWindowController(screen: screen, isMuted: isMuted)
            controller.loadVideo(url: url)
            windowControllers.append(controller)
        }

        // Synchronize native macOS desktop picture to eliminate menu bar tint & 3-finger swipe glitches
        Task { @MainActor in
            let identifier = url.lastPathComponent
            if let thumbURL = try? await ThumbnailGenerator.shared.generateThumbnail(for: url, identifier: identifier) {
                for screen in NSScreen.screens {
                    try? NSWorkspace.shared.setDesktopImageURL(thumbURL, for: screen, options: [:])
                }
            }
        }

        LumaLogger.app.info("Desktop wallpaper active on \(screens.count) screen(s)")
    }

    /// Stops and removes the live desktop wallpaper from all displays.
    public func stopWallpaper() {
        guard isDesktopActive || !windowControllers.isEmpty else { return }

        LumaLogger.app.info("Stopping desktop wallpaper")
        for controller in windowControllers {
            controller.cleanup()
        }
        windowControllers.removeAll()

        isDesktopActive = false
        isPlaying = false
        activeWallpaperURL = nil
    }

    /// Pauses playback of the active desktop wallpaper.
    public func pause() {
        for controller in windowControllers {
            controller.player.pause()
        }
        isPlaying = false
        LumaLogger.app.debug("Desktop wallpaper paused")
    }

    /// Resumes playback of the active desktop wallpaper.
    public func resume() {
        for controller in windowControllers {
            controller.player.play()
        }
        isPlaying = true
        LumaLogger.app.debug("Desktop wallpaper resumed")
    }

    /// Toggles play / pause state.
    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    /// Toggles or updates mute state for wallpaper audio.
    public func setMuted(_ muted: Bool) {
        self.isMuted = muted
        for controller in windowControllers {
            controller.player.setMuted(muted)
        }
        LumaLogger.app.debug("Desktop wallpaper mute set to: \(muted)")
    }

    // MARK: - Screen Change Handling

    private func setupScreenChangeObserver() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleScreenParametersChanged()
            }
        }
    }

    private func handleScreenParametersChanged() {
        LumaLogger.display.info("Screen parameters changed notification received")
        guard let currentURL = activeWallpaperURL, isDesktopActive else { return }

        // Reconcile displays
        let currentScreens = NSScreen.screens
        if windowControllers.count == currentScreens.count {
            // Update frames in place
            for (index, controller) in windowControllers.enumerated() {
                if index < currentScreens.count {
                    controller.updateFrame(for: currentScreens[index])
                }
            }
        } else {
            // Screen count changed: re-apply wallpaper to updated screens
            setWallpaper(url: currentURL)
        }
    }
}
