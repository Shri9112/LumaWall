import Foundation
import AppKit
import AVFoundation

public final class ThumbnailGenerator: Sendable {
    public static let shared = ThumbnailGenerator()

    public let cacheDirectory: URL

    public init(customCacheDirectory: URL? = nil) {
        if let customCacheDirectory {
            self.cacheDirectory = customCacheDirectory
        } else {
            let baseCache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.cacheDirectory = baseCache.appendingPathComponent("com.lumawall.app/thumbnails", isDirectory: true)
        }

        try? FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
    }

    /// Generates or retrieves a cached thumbnail for the video at `videoURL`.
    /// - Parameters:
    ///   - videoURL: The URL to the video file.
    ///   - identifier: A unique identifier (e.g. UUID string) for naming the cache file.
    ///   - targetTime: Specific time in seconds to capture (defaults to 0.5s).
    /// - Returns: The cached thumbnail file URL on disk.
    public func generateThumbnail(
        for videoURL: URL,
        identifier: String,
        targetTime: TimeInterval = 0.5
    ) async throws -> URL {
        let destinationURL = cacheDirectory.appendingPathComponent("\(identifier).jpg")

        // 1. Check if already cached
        if FileManager.default.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
            return destinationURL
        }

        // 2. Generate frame using AVAssetImageGenerator
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 800, height: 450)

        let durationSeconds = CMTimeGetSeconds(try await asset.load(.duration))
        let captureSeconds: Double
        if durationSeconds.isFinite && durationSeconds > 0 {
            captureSeconds = min(targetTime, durationSeconds / 2.0)
        } else {
            captureSeconds = 0.0
        }

        let cmTargetTime = CMTime(seconds: captureSeconds, preferredTimescale: 600)
        let (cgImage, _) = try await generator.image(at: cmTargetTime)

        // 3. Compress to JPEG and write to disk
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
            throw VideoValidationError.corruptedMedia("Failed to encode thumbnail image as JPEG")
        }

        try jpegData.write(to: destinationURL, options: .atomic)
        LumaLogger.video.info("Cached thumbnail for \(identifier) at \(destinationURL.lastPathComponent)")

        return destinationURL
    }

    /// Removes cached thumbnail file for the given identifier
    public func removeThumbnail(identifier: String) {
        let destinationURL = cacheDirectory.appendingPathComponent("\(identifier).jpg")
        try? FileManager.default.removeItem(at: destinationURL)
    }
}
