import Foundation
import AVFoundation
import CoreMedia

public enum VideoValidationError: LocalizedError, Equatable, Sendable {
    case fileDoesNotExist(String)
    case unsupportedExtension(String)
    case unreadableFile(String)
    case notPlayable(String)
    case noVideoTrackFound(String)
    case unsupportedCodec(String)
    case corruptedMedia(String)

    public var errorDescription: String? {
        switch self {
        case .fileDoesNotExist(let path):
            return "File does not exist at path: \(path)"
        case .unsupportedExtension(let ext):
            return "Unsupported file extension (\(ext)). LumaWall supports .mp4, .mov, and .m4v videos."
        case .unreadableFile(let reason):
            return "Unable to read video file: \(reason)"
        case .notPlayable(let name):
            return "Video format for '\(name)' is not supported by this Mac."
        case .noVideoTrackFound(let name):
            return "No playable video track was found in '\(name)'."
        case .unsupportedCodec(let codec):
            return "Video codec '\(codec)' is not supported by this Mac."
        case .corruptedMedia(let details):
            return "The video file appears to be corrupted: \(details)"
        }
    }
}

public struct VideoValidator: Sendable {
    public static let supportedExtensions: Set<String> = ["mp4", "mov", "m4v"]

    public init() {}

    /// Validates a video file at the given URL and extracts its metadata asynchronously.
    public func validate(url: URL) async throws -> VideoMetadata {
        // 1. Verify file exists
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            LumaLogger.video.error("File does not exist at path: \(path)")
            throw VideoValidationError.fileDoesNotExist(path)
        }

        // 2. Verify file extension
        let fileExtension = url.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(fileExtension) else {
            LumaLogger.video.error("Unsupported file extension: .\(fileExtension)")
            throw VideoValidationError.unsupportedExtension(fileExtension)
        }

        // 3. Inspect file size
        let fileSize: Int64
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            fileSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        } catch {
            LumaLogger.video.error("Failed to read file attributes: \(error.localizedDescription)")
            throw VideoValidationError.unreadableFile(error.localizedDescription)
        }

        guard fileSize > 0 else {
            throw VideoValidationError.corruptedMedia("File size is 0 bytes")
        }

        // 4. Load AVURLAsset
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])

        // Verify playable
        let isPlayable: Bool
        do {
            isPlayable = try await asset.load(.isPlayable)
        } catch {
            LumaLogger.video.error("Failed to check if playable: \(error.localizedDescription)")
            throw VideoValidationError.notPlayable(url.lastPathComponent)
        }

        guard isPlayable else {
            LumaLogger.video.error("Asset reports not playable: \(url.lastPathComponent)")
            throw VideoValidationError.notPlayable(url.lastPathComponent)
        }

        // 5. Inspect Tracks
        let tracks: [AVAssetTrack]
        do {
            tracks = try await asset.load(.tracks)
        } catch {
            throw VideoValidationError.corruptedMedia("Failed to load media tracks: \(error.localizedDescription)")
        }

        let videoTracks = tracks.filter { $0.mediaType == .video }
        guard let videoTrack = videoTracks.first else {
            throw VideoValidationError.noVideoTrackFound(url.lastPathComponent)
        }

        let hasAudio = tracks.contains { $0.mediaType == .audio }

        // 6. Inspect Dimensions & Transform
        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let transformedSize = naturalSize.applying(transform)
        let width = Int(abs(transformedSize.width).rounded())
        let height = Int(abs(transformedSize.height).rounded())

        guard width > 0 && height > 0 else {
            throw VideoValidationError.corruptedMedia("Invalid video dimensions (\(width)x\(height))")
        }

        // 7. Inspect Duration
        let durationCMTime = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(durationCMTime)
        let duration = (durationSeconds.isFinite && durationSeconds > 0) ? durationSeconds : 0.0

        // 8. Inspect Frame Rate
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)

        // 9. Inspect Codec
        let codec = try await parseCodec(from: videoTrack)

        let metadata = VideoMetadata(
            duration: duration,
            width: width,
            height: height,
            frameRate: nominalFrameRate,
            codec: codec,
            fileSize: fileSize,
            hasAudio: hasAudio
        )

        LumaLogger.video.info("Successfully validated video '\(url.lastPathComponent)': \(metadata.resolutionDescription), \(metadata.codec), \(metadata.formattedDuration)")
        return metadata
    }

    private func parseCodec(from track: AVAssetTrack) async throws -> String {
        let descriptions = try await track.load(.formatDescriptions)
        guard let desc = descriptions.first else {
            return "Unknown"
        }

        let subType = CMFormatDescriptionGetMediaSubType(desc)
        return friendlyCodecName(for: subType)
    }

    private func friendlyCodecName(for code: FourCharCode) -> String {
        switch code {
        case kCMVideoCodecType_H264:
            return "H.264 / AVC"
        case kCMVideoCodecType_HEVC:
            return "HEVC / H.265"
        case kCMVideoCodecType_HEVCWithAlpha:
            return "HEVC with Alpha"
        case kCMVideoCodecType_AppleProRes422:
            return "Apple ProRes 422"
        case kCMVideoCodecType_AppleProRes4444:
            return "Apple ProRes 4444"
        case kCMVideoCodecType_AppleProRes422HQ:
            return "Apple ProRes 422 HQ"
        case kCMVideoCodecType_AppleProRes422LT:
            return "Apple ProRes 422 LT"
        case kCMVideoCodecType_AppleProRes422Proxy:
            return "Apple ProRes 422 Proxy"
        default:
            return fourCCToString(code)
        }
    }

    private func fourCCToString(_ code: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff)
        ]
        let str = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return str.isEmpty ? "Unknown" : str.uppercased()
    }
}
