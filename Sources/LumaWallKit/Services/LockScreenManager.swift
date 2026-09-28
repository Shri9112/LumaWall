import Foundation
import AppKit

/// Coordinates Lock Screen live motion and seamless unlock transitions
/// with macOS 26 WallpaperAgent and com.apple.wallpaper extension.
@MainActor
public final class LockScreenManager {
    public static let shared = LockScreenManager()

    public static let extensionIdentifier = "com.lumawall.app.wallpaper-extension"
    public static let configurationToken = "lumawall-desktop-current".data(using: .utf8) ?? Data()

    private let storeURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
    }()

    private let activeConfigURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/LumaWall/active_lockscreen.json")
    }()

    private init() {}

    /// Stages a video and its thumbnail for the Lock Screen and updates macOS WallpaperAgent
    public func stageLockScreen(videoURL: URL, thumbnailURL: URL) {
        LumaLogger.app.info("LockScreenManager: Staging video for Lock Screen: \(videoURL.lastPathComponent)")

        // 1. Write active lock screen config
        let parentDir = activeConfigURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        let configDict: [String: Any] = [
            "videoPath": videoURL.path,
            "thumbnailPath": thumbnailURL.path,
            "isMuted": true
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: configDict, options: [.prettyPrinted]) {
            try? jsonData.write(to: activeConfigURL, options: .atomic)
        }

        // 2. Notify Extension
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName("com.lumawall.app.lockscreen-changed" as CFString),
            nil,
            nil,
            true
        )

        // 3. Update macOS WallpaperAgent Index.plist store
        updateAppleWallpaperStore()
    }

    /// Configures Apple's Index.plist to delegate Idle / Lock Screen to LumaWall's extension
    private func updateAppleWallpaperStore() {
        guard FileManager.default.fileExists(atPath: storeURL.path),
              let data = try? Data(contentsOf: storeURL) else {
            return
        }

        var format = PropertyListSerialization.PropertyListFormat.binary
        guard var plist = (try? PropertyListSerialization.propertyList(from: data, options: .mutableContainersAndLeaves, format: &format)) as? [String: Any] else {
            return
        }

        // Create backup once
        let backupURL = storeURL.appendingPathExtension("lumawall.bak")
        if !FileManager.default.fileExists(atPath: backupURL.path) {
            try? FileManager.default.copyItem(at: storeURL, to: backupURL)
        }

        let idleChoice: [String: Any] = [
            "Provider": Self.extensionIdentifier,
            "Configuration": Self.configurationToken,
            "Files": []
        ]

        let idleContent: [String: Any] = [
            "Choices": [idleChoice],
            "Shuffle": "$null"
        ]

        let idleNode: [String: Any] = [
            "Content": idleContent,
            "LastSet": Date(),
            "LastUse": Date()
        ]

        // Update SystemDefault
        if var sysDefault = plist["SystemDefault"] as? [String: Any] {
            sysDefault["Idle"] = idleNode
            plist["SystemDefault"] = sysDefault
        }

        // Update Spaces and Displays
        if var spaces = plist["Spaces"] as? [String: Any] {
            for (spaceKey, spaceVal) in spaces {
                guard var spaceDict = spaceVal as? [String: Any] else { continue }
                if var def = spaceDict["Default"] as? [String: Any] {
                    def["Idle"] = idleNode
                    spaceDict["Default"] = def
                }
                if var displays = spaceDict["Displays"] as? [String: Any] {
                    for (dispKey, dispVal) in displays {
                        guard var dispDict = dispVal as? [String: Any] else { continue }
                        dispDict["Idle"] = idleNode
                        displays[dispKey] = dispDict
                    }
                    spaceDict["Displays"] = displays
                }
                spaces[spaceKey] = spaceDict
            }
            plist["Spaces"] = spaces
        }

        // Write back atomically
        if let updatedData = try? PropertyListSerialization.data(fromPropertyList: plist, format: format, options: 0) {
            try? updatedData.write(to: storeURL, options: .atomic)
            LumaLogger.app.info("LockScreenManager: Successfully updated Apple WallpaperStore Index.plist")

            // Signal WallpaperAgent to refresh
            let task = Process()
            task.launchPath = "/usr/bin/killall"
            task.arguments = ["WallpaperAgent"]
            try? task.run()
        }
    }
}
