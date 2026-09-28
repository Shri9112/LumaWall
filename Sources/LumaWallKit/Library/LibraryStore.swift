import Foundation

public struct LibraryData: Codable, Sendable {
    public var version: Int
    public var wallpapers: [WallpaperItem]
    public var activeWallpaperId: UUID?
    public var displaySettings: DisplaySettings

    public init(
        version: Int = 1,
        wallpapers: [WallpaperItem] = [],
        activeWallpaperId: UUID? = nil,
        displaySettings: DisplaySettings = DisplaySettings()
    ) {
        self.version = version
        self.wallpapers = wallpapers
        self.activeWallpaperId = activeWallpaperId
        self.displaySettings = displaySettings
    }
}

public final class LibraryStore: Sendable {
    public let storeURL: URL

    public init(customStoreURL: URL? = nil) {
        if let customStoreURL {
            self.storeURL = customStoreURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let directory = appSupport.appendingPathComponent("LumaWall", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.storeURL = directory.appendingPathComponent("library.json")
        }
    }

    /// Loads the library data from disk. Returns empty LibraryData if file doesn't exist.
    public func load() throws -> LibraryData {
        let path = storeURL.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            LumaLogger.library.info("No existing library file found at \(path), returning empty library")
            return LibraryData()
        }

        let data = try Data(contentsOf: storeURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let libraryData = try decoder.decode(LibraryData.self, from: data)
        LumaLogger.library.info("Loaded \(libraryData.wallpapers.count) wallpapers from library store")
        return libraryData
    }

    /// Persists the library data atomically to disk.
    public func save(_ libraryData: LibraryData) throws {
        let parentDir = storeURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(libraryData)
        try data.write(to: storeURL, options: .atomic)
        LumaLogger.library.info("Saved \(libraryData.wallpapers.count) wallpapers to library store")
    }

    /// Deletes the library file from disk
    public func deleteStore() {
        try? FileManager.default.removeItem(at: storeURL)
    }
}
