import Foundation

public struct WallpaperItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var fileURL: URL
    public var bookmarkData: Data?
    public var duration: TimeInterval
    public var width: Int
    public var height: Int
    public var codec: String?
    public var fileSize: Int64
    public var thumbnailFileName: String?
    public var dateAdded: Date
    public var isFavorite: Bool
    public var lastUsed: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        fileURL: URL,
        bookmarkData: Data? = nil,
        duration: TimeInterval = 0,
        width: Int = 0,
        height: Int = 0,
        codec: String? = nil,
        fileSize: Int64 = 0,
        thumbnailFileName: String? = nil,
        dateAdded: Date = Date(),
        isFavorite: Bool = false,
        lastUsed: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.fileURL = fileURL
        self.bookmarkData = bookmarkData
        self.duration = duration
        self.width = width
        self.height = height
        self.codec = codec
        self.fileSize = fileSize
        self.thumbnailFileName = thumbnailFileName
        self.dateAdded = dateAdded
        self.isFavorite = isFavorite
        self.lastUsed = lastUsed
    }

    public var resolutionDescription: String {
        guard width > 0 && height > 0 else { return "Unknown" }
        if width >= 3840 || height >= 2160 {
            return "4K UHD (\(width)×\(height))"
        } else if width >= 2560 || height >= 1440 {
            return "1440p QHD (\(width)×\(height))"
        } else if width >= 1920 || height >= 1080 {
            return "1080p FHD (\(width)×\(height))"
        } else {
            return "\(width)×\(height)"
        }
    }

    public var formattedDuration: String {
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    public var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}
