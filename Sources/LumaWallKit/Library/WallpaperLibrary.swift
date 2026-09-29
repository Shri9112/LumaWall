import Foundation
import Observation

/// The central state manager for the local wallpaper library.
@Observable
@MainActor
public final class WallpaperLibrary {
    public static let shared = WallpaperLibrary()

    public private(set) var wallpapers: [WallpaperItem] = []
    public var selectedWallpaperId: UUID?
    public private(set) var activeDesktopWallpaperId: UUID?
    public var searchText: String = ""
    public var filterFavoritesOnly: Bool = false

    private let store: LibraryStore
    private let validator: VideoValidator
    private let thumbnailGenerator: ThumbnailGenerator

    public init(
        store: LibraryStore = LibraryStore(),
        validator: VideoValidator = VideoValidator(),
        thumbnailGenerator: ThumbnailGenerator = ThumbnailGenerator.shared
    ) {
        self.store = store
        self.validator = validator
        self.thumbnailGenerator = thumbnailGenerator

        loadLibrary()
    }

    // MARK: - Computed Properties

    public var filteredWallpapers: [WallpaperItem] {
        wallpapers.filter { item in
            if filterFavoritesOnly && !item.isFavorite {
                return false
            }
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let query = searchText.lowercased()
                let matchesName = item.name.lowercased().contains(query)
                let matchesCodec = (item.codec ?? "").lowercased().contains(query)
                let matchesRes = item.resolutionDescription.lowercased().contains(query)
                if !matchesName && !matchesCodec && !matchesRes {
                    return false
                }
            }
            return true
        }
    }

    public var selectedWallpaper: WallpaperItem? {
        guard let id = selectedWallpaperId else { return nil }
        return wallpapers.first { $0.id == id }
    }

    public var activeDesktopWallpaper: WallpaperItem? {
        guard let id = activeDesktopWallpaperId else { return nil }
        return wallpapers.first { $0.id == id }
    }

    // MARK: - Persistence Lifecycle

    public func loadLibrary() {
        do {
            let data = try store.load()
            var loadedItems = data.wallpapers

            // Resolve bookmarks and refresh file accessibility
            for index in loadedItems.indices {
                loadedItems[index].resolveBookmarkIfNeeded()
            }

            self.wallpapers = loadedItems
            self.activeDesktopWallpaperId = data.activeWallpaperId
            DisplayManager.shared.settings = data.displaySettings

            if selectedWallpaperId == nil, let first = wallpapers.first {
                selectedWallpaperId = first.id
            }

            LumaLogger.library.info("Loaded \(self.wallpapers.count) items into WallpaperLibrary")
        } catch {
            LumaLogger.library.error("Failed to load library: \(error.localizedDescription)")
            self.wallpapers = []
        }
    }

    public func persist() {
        let data = LibraryData(
            version: 1,
            wallpapers: wallpapers,
            activeWallpaperId: activeDesktopWallpaperId,
            displaySettings: DisplayManager.shared.settings
        )
        do {
            try store.save(data)
        } catch {
            LumaLogger.library.error("Failed to persist library: \(error.localizedDescription)")
        }
    }

    // MARK: - Library Operations

    /// Adds a video from local disk into the library. Does NOT copy the video file.
    @discardableResult
    public func addWallpaper(from url: URL) async throws -> WallpaperItem {
        LumaLogger.library.info("Adding wallpaper from: \(url.path(percentEncoded: false))")

        // 1. Check if already exists in library
        let normalizedPath = url.path(percentEncoded: false)
        if let existing = wallpapers.first(where: { $0.fileURL.path(percentEncoded: false) == normalizedPath }) {
            selectedWallpaperId = existing.id
            return existing
        }

        // 2. Validate video media
        let metadata = try await validator.validate(url: url)

        // 3. Security-scoped bookmark
        let bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        // 4. Generate thumbnail
        let itemId = UUID()
        var thumbnailFileName: String?
        do {
            let thumbURL = try await thumbnailGenerator.generateThumbnail(for: url, identifier: itemId.uuidString)
            thumbnailFileName = thumbURL.lastPathComponent
        } catch {
            LumaLogger.video.warning("Thumbnail generation skipped or failed: \(error.localizedDescription)")
        }

        // 5. Construct WallpaperItem
        let displayName = url.deletingPathExtension().lastPathComponent
        let item = WallpaperItem(
            id: itemId,
            name: displayName,
            fileURL: url,
            bookmarkData: bookmark,
            duration: metadata.duration,
            width: metadata.width,
            height: metadata.height,
            codec: metadata.codec,
            fileSize: metadata.fileSize,
            thumbnailFileName: thumbnailFileName,
            dateAdded: Date(),
            isFavorite: false,
            lastUsed: nil
        )

        wallpapers.insert(item, at: 0)
        selectedWallpaperId = item.id
        persist()

        // Auto-deploy to extension library so it appears in System Settings
        Task {
            _ = try? await VideoDeploymentService.deployVideo(url: url, name: displayName)
        }

        LumaLogger.library.info("Added wallpaper '\(item.name)' (\(item.resolutionDescription))")
        return item
    }

    /// Removes a wallpaper from the library and cleans up cached thumbnails.
    public func removeWallpaper(id: UUID) {
        guard let index = wallpapers.firstIndex(where: { $0.id == id }) else { return }
        let item = wallpapers[index]

        // If currently active on desktop, stop it
        if activeDesktopWallpaperId == id {
            stopDesktop()
        }

        // Remove thumbnail
        thumbnailGenerator.removeThumbnail(identifier: id.uuidString)

        wallpapers.remove(at: index)

        // Adjust selection
        if selectedWallpaperId == id {
            selectedWallpaperId = wallpapers.first?.id
        }

        persist()
        LumaLogger.library.info("Removed wallpaper '\(item.name)'")
    }

    /// Toggles the favorite status of a wallpaper.
    public func toggleFavorite(id: UUID) {
        guard let index = wallpapers.firstIndex(where: { $0.id == id }) else { return }
        wallpapers[index].isFavorite.toggle()
        persist()
    }

    /// Sets the wallpaper with the given ID as the active desktop & lock screen wallpaper natively via macOS WallpaperAgent.
    public func setAsDesktop(id: UUID) {
        guard let index = wallpapers.firstIndex(where: { $0.id == id }) else { return }
        let item = wallpapers[index]

        guard item.isAvailable else {
            LumaLogger.library.error("Cannot set wallpaper '\(item.name)' because file is missing")
            return
        }

        // Clean up any legacy floating windows
        WallpaperEngine.shared.stopWallpaper()
        DisplayManager.shared.stopAll()

        // Deploy to sandboxed extension and configure macOS WallpaperAgent
        Task { @MainActor in
            do {
                let entryID = try await VideoDeploymentService.deployVideo(url: item.fileURL, name: item.name)
                VideoDeploymentService.applyToSystemWallpaper(entryID: entryID)
                LumaLogger.library.info("Successfully set native wallpaper '\(item.name)' for desktop & lock screen")
            } catch {
                LumaLogger.library.error("Failed to deploy native wallpaper: \(error.localizedDescription)")
            }
        }

        wallpapers[index].lastUsed = Date()
        activeDesktopWallpaperId = id
        persist()
    }

    /// Stops desktop wallpaper playback.
    public func stopDesktop() {
        WallpaperEngine.shared.stopWallpaper()
        DisplayManager.shared.stopAll()
        activeDesktopWallpaperId = nil
        persist()
    }

    /// Renames a wallpaper item.
    public func renameWallpaper(id: UUID, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = wallpapers.firstIndex(where: { $0.id == id }) else { return }
        wallpapers[index].name = trimmed
        persist()
    }
}
