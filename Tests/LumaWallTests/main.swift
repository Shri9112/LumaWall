import Foundation
import AVFoundation
import CoreMedia
import LumaWallKit

@MainActor
struct TestRunner {
    static var passed = 0
    static var failed = 0

    static func assert(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
        if condition {
            passed += 1
            print("  ✓ \(message)")
        } else {
            failed += 1
            print("  ✗ FAILED: \(message) (\(file):\(line))")
        }
    }

    static func runSuite(_ name: String, tests: () async throws -> Void) async {
        print("\n🧪 Running Suite: \(name)")
        do {
            try await tests()
        } catch {
            failed += 1
            print("  ✗ Suite error: \(error)")
        }
    }
}

// MARK: - Test Helpers

func createSyntheticTestVideo(at url: URL) async throws {
    let writer = try AVAssetWriter(url: url, fileType: .mp4)
    let settings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: 1920,
        AVVideoHeightKey: 1080
    ]
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)

    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    var pixelBuffer: CVPixelBuffer?
    CVPixelBufferCreate(kCFAllocatorDefault, 1920, 1080, kCVPixelFormatType_32ARGB, nil, &pixelBuffer)

    if let pb = pixelBuffer {
        adaptor.append(pb, withPresentationTime: .zero)
        let frameDuration = CMTime(value: 30, timescale: 30) // 1 second
        adaptor.append(pb, withPresentationTime: frameDuration)
    }

    input.markAsFinished()
    await writer.finishWriting()
}

// MARK: - Runner Entry Point

@main
@MainActor
struct TestsMain {
    static func testWallpaperItemInitialization() {
        let dummyURL = URL(fileURLWithPath: "/Users/test/Movies/test.mp4")
        let item = WallpaperItem(
            name: "Test Wallpaper",
            fileURL: dummyURL,
            duration: 125.0,
            width: 3840,
            height: 2160,
            codec: "hevc",
            fileSize: 104_857_600
        )

        TestRunner.assert(item.name == "Test Wallpaper", "Item retains given name")
        TestRunner.assert(item.resolutionDescription.contains("4K UHD"), "Correct 4K resolution description")
        TestRunner.assert(item.formattedDuration == "2:05", "Correct duration formatting (2:05)")
        TestRunner.assert(item.formattedFileSize.contains("MB") || item.formattedFileSize.contains("100"), "Formatted file size contains MB")
        TestRunner.assert(!item.isFavorite, "Default isFavorite is false")
    }

    static func testVideoMetadataFormatting() {
        let metadata4K = VideoMetadata(
            duration: 65.4,
            width: 3840,
            height: 2160,
            frameRate: 60.0,
            codec: "HEVC / H.265",
            fileSize: 52_428_800,
            hasAudio: false
        )
        TestRunner.assert(metadata4K.resolutionDescription.starts(with: "4K UHD"), "Metadata identifies 4K UHD")
        TestRunner.assert(metadata4K.formattedDuration == "1:05", "Metadata formats 65.4s as 1:05")
        TestRunner.assert(metadata4K.formattedFrameRate == "60 fps", "Metadata formats frame rate as 60 fps")
        TestRunner.assert(!metadata4K.hasAudio, "Metadata correctly reports no audio")

        let metadata1080p = VideoMetadata(
            duration: 30.0,
            width: 1920,
            height: 1080,
            frameRate: 29.97,
            codec: "H.264 / AVC",
            fileSize: 10_000_000,
            hasAudio: true
        )
        TestRunner.assert(metadata1080p.resolutionDescription.starts(with: "1080p FHD"), "Metadata identifies 1080p FHD")
        TestRunner.assert(metadata1080p.hasAudio, "Metadata correctly reports audio track present")
    }

    static func testVideoValidatorRejections() async {
        let validator = VideoValidator()

        // Test non-existent file
        let missingURL = URL(fileURLWithPath: "/tmp/non_existent_video_file_99999.mp4")
        do {
            _ = try await validator.validate(url: missingURL)
            TestRunner.assert(false, "Should have thrown for missing file")
        } catch let error as VideoValidationError {
            switch error {
            case .fileDoesNotExist:
                TestRunner.assert(true, "Correctly rejected non-existent file")
            default:
                TestRunner.assert(false, "Wrong error type: \(error)")
            }
        } catch {
            TestRunner.assert(false, "Unexpected error: \(error)")
        }

        // Test unsupported extension
        let tempTextURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_unsupported.txt")
        try? "some text content".write(to: tempTextURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempTextURL) }

        do {
            _ = try await validator.validate(url: tempTextURL)
            TestRunner.assert(false, "Should have thrown for unsupported extension")
        } catch let error as VideoValidationError {
            switch error {
            case .unsupportedExtension(let ext):
                TestRunner.assert(ext == "txt", "Correctly rejected unsupported .txt extension")
            default:
                TestRunner.assert(false, "Wrong error type: \(error)")
            }
        } catch {
            TestRunner.assert(false, "Unexpected error: \(error)")
        }
    }

    static func testEndToEndValidationAndThumbnail() async {
        let tempVideoURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("luma_test_video.mp4")
        try? FileManager.default.removeItem(at: tempVideoURL)
        defer { try? FileManager.default.removeItem(at: tempVideoURL) }

        do {
            try await createSyntheticTestVideo(at: tempVideoURL)
            TestRunner.assert(FileManager.default.fileExists(atPath: tempVideoURL.path), "Synthetic test video created")

            let validator = VideoValidator()
            let meta = try await validator.validate(url: tempVideoURL)

            TestRunner.assert(meta.width == 1920 && meta.height == 1080, "Extracted exact 1920x1080 dimensions")
            TestRunner.assert(meta.codec == "H.264 / AVC", "Extracted codec: \(meta.codec)")
            TestRunner.assert(meta.resolutionDescription.contains("1080p FHD"), "Formatted as 1080p FHD")

            // Test thumbnail generator
            let thumbGen = ThumbnailGenerator.shared
            let testUUID = UUID().uuidString
            let thumbURL = try await thumbGen.generateThumbnail(for: tempVideoURL, identifier: testUUID)
            defer { thumbGen.removeThumbnail(identifier: testUUID) }

            TestRunner.assert(FileManager.default.fileExists(atPath: thumbURL.path), "Thumbnail image generated on disk")
        } catch {
            TestRunner.assert(false, "Synthetic video validation failed: \(error)")
        }
    }

    static func main() async {
        print("========================================")
        print("  LumaWall Automated Test Suite")
        print("========================================")

        await TestRunner.runSuite("WallpaperItem Tests") {
            testWallpaperItemInitialization()
        }

        await TestRunner.runSuite("VideoMetadata Tests") {
            testVideoMetadataFormatting()
        }

        await TestRunner.runSuite("VideoValidator Rejection Tests") {
            await testVideoValidatorRejections()
        }

        await TestRunner.runSuite("End-to-End Video Validation & Thumbnail Tests") {
            await testEndToEndValidationAndThumbnail()
        }

        print("\n========================================")
        print("Results: \(TestRunner.passed) passed, \(TestRunner.failed) failed")
        print("========================================")

        if TestRunner.failed > 0 {
            exit(1)
        }
    }
}
