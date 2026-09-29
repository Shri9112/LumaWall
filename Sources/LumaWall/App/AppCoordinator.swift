import AppKit
import Foundation
import LumaWallKit

/// Manages high-level application startup, state restoration, and clean termination.
@MainActor
public final class AppCoordinator {
    public static let shared = AppCoordinator()

    private var hasStarted = false

    private init() {
        setupTerminationObserver()
    }

    /// Executed on application startup to restore previous wallpaper state if enabled.
    public func startup() {
        guard !hasStarted else { return }
        hasStarted = true

        LumaLogger.app.info("AppCoordinator: performing startup initialization")

        let library = WallpaperLibrary.shared
        let displayManager = DisplayManager.shared
        let powerManager = PowerManager.shared

        // Synchronize settings
        powerManager.settings = library.filteredWallpapers.isEmpty ? AppSettings() : (try? LibraryStore().load())?.appSettings ?? AppSettings()

        // Check auto-start preference
        if powerManager.settings.autoStartOnLaunch {
            LumaLogger.app.info("Auto-start on launch enabled: restoring last configured wallpaper")
            restoreLastWallpaperState(library: library, displayManager: displayManager)
        }

        // Synchronize all library items to LumaWallWallpaperExtension container
        Task {
            for item in library.wallpapers where item.isAvailable {
                _ = try? await VideoDeploymentService.deployVideo(url: item.fileURL, name: item.name)
            }
        }
    }

    private func restoreLastWallpaperState(library: WallpaperLibrary, displayManager: DisplayManager) {
        // macOS WallpaperAgent handles desktop and lock screen playback persistence natively.
        // We ensure any legacy floating windows are cleaned up.
        displayManager.stopAll()
        WallpaperEngine.shared.stopWallpaper()
    }

    /// Brings the main LumaWall window to the front
    public func showMainWindow() {
        MainWindowController.shared.showWindow()
    }

    /// Shuts down all wallpaper playback and terminates the application cleanly
    public func quit() {
        LumaLogger.app.info("AppCoordinator: cleanly shutting down LumaWall")
        MainWindowController.shared.hideWindow()
        DisplayManager.shared.stopAll()
        WallpaperEngine.shared.stopWallpaper()
        NSApp.terminate(nil)
    }

    private func setupTerminationObserver() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                LumaLogger.app.info("Application will terminate: stopping all desktop windows")
                DisplayManager.shared.stopAll()
                WallpaperEngine.shared.stopWallpaper()
            }
        }
    }
}
