import AppKit
import AVFoundation
import Foundation
import os

/// Models a video entry matching the extension's `VideoEntry` Codable schema.
public struct DeployedVideoEntry: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public var name: String
    public var filename: String
    public var duration: Double
    public var fps: Double
    public var resolution: CGSize
    public var dateAdded: Date
    public var variants: [DeployedVideoVariant]?

    public init(
        id: String,
        name: String,
        filename: String,
        duration: Double,
        fps: Double,
        resolution: CGSize,
        dateAdded: Date,
        variants: [DeployedVideoVariant]? = nil
    ) {
        self.id = id
        self.name = name
        self.filename = filename
        self.duration = duration
        self.fps = fps
        self.resolution = resolution
        self.dateAdded = dateAdded
        self.variants = variants
    }
}

public struct DeployedVideoVariant: Codable, Sendable, Equatable {
    public let filename: String
    public let fps: Int
    public let resolution: CGSize

    public init(filename: String, fps: Int, resolution: CGSize) {
        self.filename = filename
        self.fps = fps
        self.resolution = resolution
    }
}

/// Service that coordinates deploying video wallpapers into the sandboxed extension's container,
/// generating metadata and thumbnails, signaling the extension, and applying choices to macOS WallpaperAgent.
@MainActor
public enum VideoDeploymentService {
    public static let extensionBundleID = "com.lumawall.app.wallpaper-extension"

    /// Extension container Documents directory where LumaWallWallpaperExtension discovers library items.
    public static var extensionDocsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(extensionBundleID)/Data/Documents")
    }

    /// The library folder holding UUID subfolders per video (media + metadata.json + thumbnail.jpg).
    public static var videosFolderURL: URL {
        extensionDocsURL.appendingPathComponent("videos")
    }

    public static let libraryChangedNotification = Notification.Name("com.lumawall.app.libraryChanged")

    // MARK: - Deployment Pipeline

    /// Deploys a video file into the extension's sandbox library structure:
    /// `Documents/videos/<UUID>/<filename>` + `metadata.json` + `thumbnail.jpg`.
    /// Probes fps, resolution, and duration with AVFoundation.
    /// Notifies LumaWallWallpaperExtension via Darwin notification so it updates live and pushes to System Settings.
    @discardableResult
    public static func deployVideo(url: URL, name: String? = nil) async throws -> String {
        let fileManager = FileManager.default
        let videosDir = videosFolderURL
        try fileManager.createDirectory(at: videosDir, withIntermediateDirectories: true)

        // Deduplicate: if a video with this filename already exists, return its ID
        let existing = listEntries()
        if let match = existing.first(where: { $0.filename == url.lastPathComponent }) {
            LumaLogger.video.info("Video '\(url.lastPathComponent)' already in extension library (id: \(match.id))")
            notifyExtensionLibraryChanged()
            return match.id
        }

        let id = UUID().uuidString
        let dir = videosDir.appendingPathComponent(id)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        let destURL = dir.appendingPathComponent(url.lastPathComponent)
        do {
            try fileManager.copyItem(at: url, to: destURL)

            var fps: Double = 30
            var resolution: CGSize = .zero
            var duration: Double = 0

            let asset = AVURLAsset(url: destURL)
            if let track = try? await asset.loadTracks(withMediaType: .video).first {
                fps = await Double((try? track.load(.nominalFrameRate)) ?? 30)
                resolution = await (try? track.load(.naturalSize)) ?? .zero
                let cmDuration = try? await asset.load(.duration)
                duration = cmDuration.map { CMTimeGetSeconds($0) } ?? 0
            }

            let displayName = name ?? VideoDisplayName.pretty(from: url.deletingPathExtension().lastPathComponent)
            let metadata = DeployedVideoEntry(
                id: id,
                name: displayName,
                filename: url.lastPathComponent,
                duration: duration,
                fps: fps > 0 ? fps : 30,
                resolution: resolution,
                dateAdded: Date(),
                variants: nil
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(metadata)
            try data.write(to: dir.appendingPathComponent("metadata.json"), options: .atomic)

            await generateThumbnail(for: destURL, in: dir)

            LumaLogger.video.info("Successfully deployed video '\(url.lastPathComponent)' as \(id)")
            notifyExtensionLibraryChanged()
            return id
        } catch {
            LumaLogger.video.error("Failed to deploy video '\(url.lastPathComponent)': \(error.localizedDescription)")
            try? fileManager.removeItem(at: dir)
            throw error
        }
    }

    /// List all valid video entries in the extension container.
    public static func listEntries() -> [DeployedVideoEntry] {
        let videosDir = videosFolderURL
        let fm = FileManager.default

        guard let subdirs = try? fm.contentsOfDirectory(
            at: videosDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return [] }

        var entries = [DeployedVideoEntry]()
        for dir in subdirs where dir.hasDirectoryPath {
            let id = dir.lastPathComponent
            guard UUID(uuidString: id) != nil else { continue }

            let metadataURL = dir.appendingPathComponent("metadata.json")
            guard let data = try? Data(contentsOf: metadataURL),
                  let entry = try? JSONDecoder().decode(DeployedVideoEntry.self, from: data) else {
                continue
            }

            let videoFile = dir.appendingPathComponent(entry.filename)
            guard fm.fileExists(atPath: videoFile.path) else { continue }

            entries.append(entry)
        }

        return entries.sorted { $0.dateAdded < $1.dateAdded }
    }

    /// URL to the thumbnail for an entry, if it exists.
    public static func thumbnailURL(for entryID: String) -> URL? {
        let url = videosFolderURL
            .appendingPathComponent(entryID)
            .appendingPathComponent("thumbnail.jpg")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// URL to the video file for an entry.
    public static func videoURL(for entry: DeployedVideoEntry) -> URL {
        videosFolderURL
            .appendingPathComponent(entry.id)
            .appendingPathComponent(entry.filename)
    }

    /// Remove a video entry from the extension container.
    public static func removeVideo(entryID: String) {
        guard UUID(uuidString: entryID) != nil else { return }
        let dir = videosFolderURL.appendingPathComponent(entryID)
        try? FileManager.default.removeItem(at: dir)
        LumaLogger.video.info("Removed video entry \(entryID) from extension container")
        notifyExtensionLibraryChanged()
    }

    // MARK: - Native WallpaperAgent System Settings Integration

    /// Directly configures Apple's Index.plist to set this video as the native system wallpaper
    /// (desktop and lock screen / screensaver) rendered seamlessly by LumaWallWallpaperExtension.
    public static func applyToSystemWallpaper(entryID: String) {
        guard let entry = listEntries().first(where: { $0.id == entryID }) else {
            LumaLogger.video.error("Cannot apply wallpaper: entry \(entryID) not found in extension library")
            return
        }

        let fileURL = videoURL(for: entry)
        let storeURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")

        guard FileManager.default.fileExists(atPath: storeURL.path),
              let data = try? Data(contentsOf: storeURL) else {
            LumaLogger.video.error("Wallpaper store Index.plist not found")
            return
        }

        var format = PropertyListSerialization.PropertyListFormat.binary
        guard var plist = (try? PropertyListSerialization.propertyList(from: data, options: .mutableContainersAndLeaves, format: &format)) as? [String: Any] else {
            LumaLogger.video.error("Failed to parse wallpaper store Index.plist")
            return
        }

        // Backup once
        let backupURL = storeURL.appendingPathExtension("lumawall.bak")
        if !FileManager.default.fileExists(atPath: backupURL.path) {
            try? FileManager.default.copyItem(at: storeURL, to: backupURL)
        }

        let choice: [String: Any] = [
            "Provider": extensionBundleID,
            "Configuration": Data(entryID.utf8),
            "Files": [["relative": fileURL.absoluteString]]
        ]

        let encodedOptions: Data = {
            let emptyOpts: [String: Any] = ["values": [:] as [String: Any]]
            return (try? PropertyListSerialization.data(fromPropertyList: emptyOpts, format: .binary, options: 0)) ?? Data()
        }()

        let surfaceContent: [String: Any] = [
            "Choices": [choice],
            "EncodedOptionValues": encodedOptions,
            "Shuffle": "$null"
        ]

        let surfaceNode: [String: Any] = [
            "Content": surfaceContent,
            "LastSet": Date(),
            "LastUse": Date()
        ]

        let targetSurfaces = ["Desktop", "Linked", "Idle"]

        func applyToNode(_ node: inout [String: Any]) {
            for surface in targetSurfaces {
                node[surface] = surfaceNode
            }
        }

        // 1. Update AllSpacesAndDisplays
        if var all = plist["AllSpacesAndDisplays"] as? [String: Any] {
            applyToNode(&all)
            plist["AllSpacesAndDisplays"] = all
        }

        // 2. Update SystemDefault
        if var sysDefault = plist["SystemDefault"] as? [String: Any] {
            applyToNode(&sysDefault)
            plist["SystemDefault"] = sysDefault
        }

        // 3. Update Displays
        if var displays = plist["Displays"] as? [String: Any] {
            for (dispKey, dispVal) in displays {
                guard var dispDict = dispVal as? [String: Any] else { continue }
                applyToNode(&dispDict)
                displays[dispKey] = dispDict
            }
            plist["Displays"] = displays
        }

        // 4. Update Spaces
        if var spaces = plist["Spaces"] as? [String: Any] {
            for (spaceKey, spaceVal) in spaces {
                guard var spaceDict = spaceVal as? [String: Any] else { continue }
                if var def = spaceDict["Default"] as? [String: Any] {
                    applyToNode(&def)
                    spaceDict["Default"] = def
                }
                if var displays = spaceDict["Displays"] as? [String: Any] {
                    for (dispKey, dispVal) in displays {
                        guard var dispDict = dispVal as? [String: Any] else { continue }
                        applyToNode(&dispDict)
                        displays[dispKey] = dispDict
                    }
                    spaceDict["Displays"] = displays
                }
                spaces[spaceKey] = spaceDict
            }
        }

        if let updatedData = try? PropertyListSerialization.data(fromPropertyList: plist, format: format, options: 0) {
            try? updatedData.write(to: storeURL, options: .atomic)
            LumaLogger.video.info("Successfully updated Apple WallpaperStore Index.plist for '\(entry.name)'")

            // Restart WallpaperAgent so macOS immediately applies the new wallpaper
            let task = Process()
            task.launchPath = "/usr/bin/killall"
            task.arguments = ["WallpaperAgent"]
            try? task.run()
        }
    }

    // MARK: - Internal Helpers

    /// Generates thumbnail.jpg from the first frame of a video.
    private static func generateThumbnail(for videoURL: URL, in directory: URL) async {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 360)

        guard let cgImage = try? await generator.image(at: .zero).image else {
            LumaLogger.video.warning("Thumbnail generation failed for \(videoURL.lastPathComponent)")
            return
        }

        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
            return
        }

        let thumbnailURL = directory.appendingPathComponent("thumbnail.jpg")
        try? jpegData.write(to: thumbnailURL, options: .atomic)
    }

    /// Notifies the extension that the library contents changed.
    public static func notifyExtensionLibraryChanged() {
        writeHostViewModelCache()

        // Darwin notification to out-of-process LumaWallWallpaperExtension
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName("com.lumawall.app.libraryChanged" as CFString),
            nil,
            nil,
            true
        )

        // In-process notification
        NotificationCenter.default.post(name: libraryChangedNotification, object: nil)
    }

    /// Writes the System Settings view-model cache directly for WallpaperAgent.
    public static func writeHostViewModelCache() {
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        let length = confstr(_CS_DARWIN_USER_CACHE_DIR, &buf, buf.count)
        guard length > 0 else { return }
        let pathBytes = buf.prefix(length - 1).map { UInt8(bitPattern: $0) }
        let cacheDir = URL(fileURLWithPath: String(decoding: pathBytes, as: UTF8.self))
            .appendingPathComponent("com.apple.wallpaper.agent/com.apple.wallpaper.view-model-cache")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let entries = listEntries()
        guard !entries.isEmpty else { return }

        var items = [[String: Any]]()
        for entry in entries {
            let fileURL = videoURL(for: entry)
            let thumbURL = thumbnailURL(for: entry.id) ?? fileURL

            let choiceDict: [String: Any] = [
                "id": [
                    "descriptor": [
                        "configuration": Data(entry.id.utf8),
                        "files": [["relative": fileURL.absoluteString]],
                        "provider": extensionBundleID
                    ]
                ],
                "isDownloaded": true,
                "localizedDescription": "Animated video wallpaper",
                "options": [] as [Any],
                "thumbnail": [
                    "image": ["url": ["relative": thumbURL.absoluteString]]
                ]
            ]

            let contextMenuDict: [String: Any] = [
                "items": [
                    ["id": ["id": "add-video"], "isDestructive": false, "localizedTitle": "Add Video…"],
                    ["id": ["id": "manage-library"], "isDestructive": false, "localizedTitle": "Manage Library…"]
                ]
            ]

            let itemDict: [String: Any] = [
                "choice": choiceDict,
                "contentBadge": ["video": [:] as [String: Any]],
                "contextMenu": contextMenuDict,
                "disposability": ["none": [:] as [String: Any]],
                "id": ["id": entry.id],
                "localizedName": entry.name,
                "showInTopLevel": true,
                "sortOrder": 0,
                "thumbnail": [
                    "image": ["url": ["relative": thumbURL.absoluteString]]
                ]
            ]
            items.append(itemDict)
        }

        let groupDict: [String: Any] = [
            "disposability": ["none": [:] as [String: Any]],
            "id": ["id": "video-wallpapers"],
            "items": items,
            "localizedName": "LumaWall — Video Wallpapers",
            "shouldHideItemLabels": false,
            "sortID": ["id": "com.apple.wallpaper.aerials"],
            "sortOrder": -100
        ]

        let cacheDict: [String: Any] = [
            "osBuildVersion": "25C56",
            "viewModel": [
                "groups": [groupDict],
                "isModificationDisabled": false,
                "refreshPolicy": ["default": [:] as [String: Any]]
            ]
        ]

        if let data = try? PropertyListSerialization.data(fromPropertyList: cacheDict, format: .binary, options: 0) {
            for surface in ["desktop", "screenSaver"] {
                let file = cacheDir.appendingPathComponent("extension-\(extensionBundleID)-\(surface)")
                try? data.write(to: file, options: .atomic)
            }
        }
    }

    /// Invalidates WallpaperAgent's cached view models so System Settings re-queries the extension.
    public static func invalidateHostViewModelCache() {
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        let length = confstr(_CS_DARWIN_USER_CACHE_DIR, &buf, buf.count)
        guard length > 0 else { return }
        let pathBytes = buf.prefix(length - 1).map { UInt8(bitPattern: $0) }
        let cacheDir = URL(fileURLWithPath: String(decoding: pathBytes, as: UTF8.self))
            .appendingPathComponent("com.apple.wallpaper.agent/com.apple.wallpaper.view-model-cache")
        for surface in ["desktop", "screenSaver"] {
            let file = cacheDir
                .appendingPathComponent("extension-\(extensionBundleID)-\(surface)")
            try? FileManager.default.removeItem(at: file)
        }
    }
}
