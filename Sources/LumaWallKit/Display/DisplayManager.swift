import AppKit
import Foundation
import Observation

/// Coordinates multi-display discovery, reconfiguration, and wallpaper window controller mapping.
@Observable
@MainActor
public final class DisplayManager {
    public static let shared = DisplayManager()

    public private(set) var displays: [DisplayInfo] = []
    public var settings: DisplaySettings = DisplaySettings()
    public private(set) var isAnyDisplayActive: Bool = false
    public private(set) var isPlaying: Bool = false
    public private(set) var isMuted: Bool = true

    private var controllers: [CGDirectDisplayID: WallpaperWindowController] = [:]
    private var wallpaperCache: [UUID: WallpaperItem] = [:]
    private var screenChangeObserver: (any NSObjectProtocol)?

    public init() {
        refreshDisplays()
        setupScreenChangeObserver()
    }

    // MARK: - Display Discovery & Refresh

    public func refreshDisplays() {
        self.displays = NSScreen.screens.map { $0.displayInfo }
        LumaLogger.display.info("Detected \(self.displays.count) active display(s)")
    }

    // MARK: - Playback & Assignment Control

    /// Applies a unified wallpaper across all connected displays.
    public func setUnifiedWallpaper(item: WallpaperItem) {
        LumaLogger.display.info("Setting unified wallpaper '\(item.name)' on all displays")
        wallpaperCache[item.id] = item
        settings.mode = .unified
        settings.unifiedWallpaperId = item.id

        applyCurrentSettingsToAllScreens()
    }

    /// Sets an individual wallpaper for a specific physical display.
    public func setIndividualWallpaper(item: WallpaperItem, for displayID: CGDirectDisplayID) {
        LumaLogger.display.info("Setting individual wallpaper '\(item.name)' for display \(displayID)")
        wallpaperCache[item.id] = item
        settings.mode = .individual
        settings.assignments[displayID] = item.id

        guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else {
            LumaLogger.display.warning("Screen with ID \(displayID) not currently connected")
            return
        }

        applyWallpaper(item: item, to: screen)
        updateEngineState()
    }

    /// Stops wallpaper on a specific display.
    public func stopWallpaper(for displayID: CGDirectDisplayID) {
        if let controller = controllers.removeValue(forKey: displayID) {
            controller.cleanup()
        }
        settings.assignments.removeValue(forKey: displayID)
        updateEngineState()
    }

    /// Stops wallpaper across all displays.
    public func stopAll() {
        LumaLogger.display.info("Stopping wallpapers on all displays")
        for (_, controller) in controllers {
            controller.cleanup()
        }
        controllers.removeAll()
        settings.unifiedWallpaperId = nil
        settings.assignments.removeAll()
        updateEngineState()
    }

    /// Pauses playback across all active display windows.
    public func pauseAll() {
        for (_, controller) in controllers {
            controller.player.pause()
        }
        isPlaying = false
    }

    /// Resumes playback across all active display windows.
    public func resumeAll() {
        for (_, controller) in controllers {
            controller.player.play()
        }
        isPlaying = true
    }

    /// Toggles play / pause state across all displays.
    public func togglePlayPauseAll() {
        if isPlaying {
            pauseAll()
        } else {
            resumeAll()
        }
    }

    /// Sets mute state across all active display windows.
    public func setMutedAll(_ muted: Bool) {
        self.isMuted = muted
        for (_, controller) in controllers {
            controller.player.setMuted(muted)
        }
    }

    /// Updates the display mode and re-applies wallpapers accordingly.
    public func setDisplayMode(_ mode: DisplayMode) {
        guard settings.mode != mode else { return }
        settings.mode = mode
        LumaLogger.display.info("Display mode changed to: \(mode.title)")
        applyCurrentSettingsToAllScreens()
    }

    // MARK: - State Inspection

    public func activeWallpaperId(for displayID: CGDirectDisplayID) -> UUID? {
        switch settings.mode {
        case .unified:
            return settings.unifiedWallpaperId
        case .individual:
            return settings.assignments[displayID]
        }
    }

    public func isDisplayActive(_ displayID: CGDirectDisplayID) -> Bool {
        controllers[displayID] != nil
    }

    // MARK: - Internal Reconciliation

    public func applyCurrentSettingsToAllScreens() {
        refreshDisplays()

        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            stopAll()
            return
        }

        let library = WallpaperLibrary.shared

        for screen in screens {
            let displayID = screen.displayID ?? 0
            let targetItemId: UUID?

            switch settings.mode {
            case .unified:
                targetItemId = settings.unifiedWallpaperId
            case .individual:
                targetItemId = settings.assignments[displayID]
            }

            if let targetItemId, let item = wallpaperCache[targetItemId] ?? library.wallpapers.first(where: { $0.id == targetItemId }), item.isAvailable {
                applyWallpaper(item: item, to: screen)
            } else {
                // If no wallpaper assigned to this screen in individual mode, stop any existing controller on it
                if let controller = controllers.removeValue(forKey: displayID) {
                    controller.cleanup()
                }
            }
        }

        updateEngineState()
    }

    private func applyWallpaper(item: WallpaperItem, to screen: NSScreen) {
        let displayID = screen.displayID ?? 0

        if let existingController = controllers[displayID] {
            existingController.updateFrame(for: screen)
            existingController.loadVideo(url: item.fileURL)
        } else {
            let controller = WallpaperWindowController(screen: screen, isMuted: isMuted)
            controller.loadVideo(url: item.fileURL)
            controllers[displayID] = controller
        }
    }

    private func updateEngineState() {
        isAnyDisplayActive = !controllers.isEmpty
        isPlaying = isAnyDisplayActive && (controllers.values.first?.player.isPlaying ?? false)
    }

    // MARK: - Screen Change Notifications

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
        LumaLogger.display.info("Screen parameters changed: reconciling displays and controllers")
        refreshDisplays()

        let activeScreenIDs = Set(NSScreen.screens.compactMap { $0.displayID })

        // 1. Remove controllers for disconnected screens
        for (displayID, controller) in controllers where !activeScreenIDs.contains(displayID) {
            LumaLogger.display.info("Display \(displayID) was disconnected, cleaning up controller")
            controller.cleanup()
            controllers.removeValue(forKey: displayID)
        }

        // 2. Re-anchor frames and apply wallpapers to active screens
        applyCurrentSettingsToAllScreens()
    }
}
