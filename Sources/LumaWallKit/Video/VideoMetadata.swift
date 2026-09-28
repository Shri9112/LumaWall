import Foundation
import CoreGraphics

public struct VideoMetadata: Sendable, Equatable, Codable {
    public let duration: TimeInterval
    public let width: Int
    public let height: Int
    public let frameRate: Float
    public let codec: String
    public let fileSize: Int64
    public let hasAudio: Bool

    public init(
        duration: TimeInterval,
        width: Int,
        height: Int,
        frameRate: Float,
        codec: String,
        fileSize: Int64,
        hasAudio: Bool
    ) {
        self.duration = duration
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.codec = codec
        self.fileSize = fileSize
        self.hasAudio = hasAudio
    }

    public var resolutionDescription: String {
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
        let total = Int(duration.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    public var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    public var formattedFrameRate: String {
        if frameRate > 0 {
            return String(format: "%.0f fps", frameRate)
        }
        return "Unknown fps"
    }
}
