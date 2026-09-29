import Foundation
import AppKit

/// Coordinates Lock Screen live motion and seamless unlock transitions
/// with macOS 26 WallpaperAgent and LumaWallWallpaperExtension.
@MainActor
public final class LockScreenManager {
    public static let shared = LockScreenManager()

    public static let extensionIdentifier = "com.lumawall.app.wallpaper-extension"

    private let extensionContainerDocsURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.lumawall.app.wallpaper-extension/Data/Documents", isDirectory: true)
    }()

    private init() {}

    /// Stages a video and its thumbnail for the Lock Screen and updates macOS WallpaperAgent
    public func stageLockScreen(videoURL: URL, thumbnailURL: URL) {
        LumaLogger.app.info("LockScreenManager: Staging video for Lock Screen: \(videoURL.lastPathComponent)")

        Task { @MainActor in
            do {
                // 1. Deploy video cleanly into extension library with valid UUID & metadata
                let entryID = try await VideoDeploymentService.deployVideo(url: videoURL)

                // 2. Stage desktop still image for fallback & instantaneous transition
                let docs = self.extensionContainerDocsURL
                let desktopStillURL = docs.appendingPathComponent("desktop.jpg")
                try? FileManager.default.removeItem(at: desktopStillURL)
                try? FileManager.default.copyItem(at: thumbnailURL, to: desktopStillURL)

                for screen in NSScreen.screens {
                    try? NSWorkspace.shared.setDesktopImageURL(desktopStillURL, for: screen, options: [:])
                }

                // 3. Extract high-resolution still frame asynchronously
                Task.detached(priority: .userInitiated) {
                    do {
                        try await ThumbnailGenerator.shared.generateNativeStillFrame(for: videoURL, destinationURL: desktopStillURL)
                        await MainActor.run {
                            for screen in NSScreen.screens {
                                try? NSWorkspace.shared.setDesktopImageURL(desktopStillURL, for: screen, options: [:])
                            }
                            LumaLogger.app.info("LockScreenManager: Upgraded Lock Screen still image to native resolution")
                        }
                    } catch {
                        LumaLogger.app.warning("LockScreenManager: Native frame extraction fallback: \(error.localizedDescription)")
                    }
                }

                // 4. Delegate to Apple WallpaperStore so macOS WallpaperAgent activates LumaWallWallpaperExtension
                VideoDeploymentService.applyToSystemWallpaper(entryID: entryID)

                // 5. Signal Darwin preferences changed
                let center = CFNotificationCenterGetDarwinNotifyCenter()
                CFNotificationCenterPostNotification(
                    center,
                    CFNotificationName("com.lumawall.app.prefsChanged" as CFString),
                    nil,
                    nil,
                    true
                )
            } catch {
                LumaLogger.app.error("LockScreenManager: Staging failed: \(error.localizedDescription)")
            }
        }
    }
}
