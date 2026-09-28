import Foundation
import AppKit
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

    static func testWallpaperWindowProperties() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            TestRunner.assert(false, "No NSScreen available for window test")
            return
        }

        let window = WallpaperWindow(screen: screen)
        TestRunner.assert(window.level.rawValue == Int(CGWindowLevelForKey(.desktopWindow)), "Window level is exactly desktopWindow (-2147483623)")
        TestRunner.assert(window.ignoresMouseEvents, "Window ignores mouse events for full pass-through")
        TestRunner.assert(!window.canBecomeKey, "Window refuses key focus (canBecomeKey == false)")
        TestRunner.assert(!window.canBecomeMain, "Window refuses main status (canBecomeMain == false)")
        TestRunner.assert(!window.hasShadow, "Window has no shadow")
        TestRunner.assert(window.styleMask.contains(.borderless), "Window is borderless")
        TestRunner.assert(window.collectionBehavior.contains(.canJoinAllSpaces), "Window joins all Spaces")
        TestRunner.assert(window.collectionBehavior.contains(.stationary), "Window is stationary during Exposé")
        TestRunner.assert(window.collectionBehavior.contains(.ignoresCycle), "Window is excluded from window cycling")
        TestRunner.assert(window.collectionBehavior.contains(.fullScreenAuxiliary), "Window remains behind fullscreen spaces")
    }

    static func testWallpaperEngineLifecycle() async {
        let engine = WallpaperEngine.shared
        TestRunner.assert(!engine.isDesktopActive, "Engine initially idle")
        TestRunner.assert(engine.activeWallpaperURL == nil, "No initial active URL")

        let tempVideoURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("luma_engine_test.mp4")
        try? FileManager.default.removeItem(at: tempVideoURL)
        defer { try? FileManager.default.removeItem(at: tempVideoURL) }

        do {
            try await createSyntheticTestVideo(at: tempVideoURL)
            engine.setWallpaper(url: tempVideoURL)

            TestRunner.assert(engine.isDesktopActive, "Engine reports desktop active after setWallpaper")
            TestRunner.assert(engine.activeWallpaperURL == tempVideoURL, "Engine tracks active wallpaper URL")
            TestRunner.assert(engine.isPlaying, "Engine reports isPlaying == true")

            engine.pause()
            TestRunner.assert(!engine.isPlaying, "Engine reports isPlaying == false after pause")

            engine.resume()
            TestRunner.assert(engine.isPlaying, "Engine reports isPlaying == true after resume")

            engine.setMuted(false)
            TestRunner.assert(!engine.isMuted, "Engine updates mute state to false")

            engine.stopWallpaper()
            TestRunner.assert(!engine.isDesktopActive, "Engine reports not active after stopWallpaper")
            TestRunner.assert(engine.activeWallpaperURL == nil, "Active wallpaper URL cleared after stop")
        } catch {
            TestRunner.assert(false, "Engine lifecycle test failed: \(error)")
        }
    }

    static func testLibraryStorePersistence() {
        let tempStoreURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_library_\(UUID().uuidString).json")
        let store = LibraryStore(customStoreURL: tempStoreURL)
        defer { store.deleteStore() }

        // Test loading empty
        let initialData = try? store.load()
        TestRunner.assert(initialData?.wallpapers.isEmpty == true, "Empty store returns empty list")

        // Test saving and reloading
        let item1 = WallpaperItem(
            name: "Hogwarts",
            fileURL: URL(fileURLWithPath: "/Users/test/Movies/Hogwarts.mp4"),
            duration: 60.0,
            width: 3840,
            height: 2160,
            codec: "hevc",
            fileSize: 50_000_000
        )
        let item2 = WallpaperItem(
            name: "Spider-Man",
            fileURL: URL(fileURLWithPath: "/Users/test/Movies/SpiderMan.mp4"),
            duration: 90.0,
            width: 1920,
            height: 1080,
            codec: "avc1",
            fileSize: 30_000_000,
            isFavorite: true
        )

        let toSave = LibraryData(version: 1, wallpapers: [item1, item2], activeWallpaperId: item1.id)
        try? store.save(toSave)

        let loaded = try? store.load()
        TestRunner.assert(loaded?.wallpapers.count == 2, "Reloaded exact item count (2)")
        TestRunner.assert(loaded?.wallpapers[0].name == "Hogwarts", "Preserved item 1 name")
        TestRunner.assert(loaded?.wallpapers[1].isFavorite == true, "Preserved item 2 favorite status")
        TestRunner.assert(loaded?.activeWallpaperId == item1.id, "Preserved activeWallpaperId")
    }

    static func testWallpaperLibraryOperations() async {
        let tempStoreURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_lib_mgr_\(UUID().uuidString).json")
        let store = LibraryStore(customStoreURL: tempStoreURL)
        defer { store.deleteStore() }

        let library = WallpaperLibrary(store: store)
        TestRunner.assert(library.wallpapers.isEmpty, "New library is empty")

        let tempVideoURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("luma_lib_test.mp4")
        try? FileManager.default.removeItem(at: tempVideoURL)
        defer { try? FileManager.default.removeItem(at: tempVideoURL) }

        do {
            try await createSyntheticTestVideo(at: tempVideoURL)
            let added = try await library.addWallpaper(from: tempVideoURL)

            TestRunner.assert(library.wallpapers.count == 1, "Wallpaper added to library")
            TestRunner.assert(library.selectedWallpaperId == added.id, "Newly added item is selected")
            TestRunner.assert(added.isAvailable, "Added file is available on disk")

            // Test search
            library.searchText = "luma"
            TestRunner.assert(library.filteredWallpapers.count == 1, "Search matches name")
            library.searchText = "nonexistent_query"
            TestRunner.assert(library.filteredWallpapers.isEmpty, "Search excludes non-matching")
            library.searchText = ""

            // Test favorite toggle
            library.toggleFavorite(id: added.id)
            TestRunner.assert(library.wallpapers.first?.isFavorite == true, "Wallpaper is favorite")
            library.filterFavoritesOnly = true
            TestRunner.assert(library.filteredWallpapers.count == 1, "Filter favorites includes item")
            library.filterFavoritesOnly = false

            // Test set as desktop
            library.setAsDesktop(id: added.id)
            TestRunner.assert(library.activeDesktopWallpaperId == added.id, "Item marked as active on desktop")
            TestRunner.assert(library.activeDesktopWallpaper?.id == added.id, "activeDesktopWallpaper returns item")

            library.stopDesktop()
            TestRunner.assert(library.activeDesktopWallpaperId == nil, "Active desktop cleared after stop")

            // Test missing file handling
            let missingItem = WallpaperItem(
                name: "Deleted Video",
                fileURL: URL(fileURLWithPath: "/tmp/this_file_does_not_exist_98765.mp4")
            )
            TestRunner.assert(!missingItem.isAvailable, "Item correctly marked as unavailable when file is missing")

            // Test remove
            library.removeWallpaper(id: added.id)
            TestRunner.assert(library.wallpapers.isEmpty, "Wallpaper removed from library")
        } catch {
            TestRunner.assert(false, "Library operations test failed: \(error)")
        }
    }

    static func testDisplayManagerAndConfigurations() async {
        let displayManager = DisplayManager.shared
        displayManager.refreshDisplays()

        TestRunner.assert(!displayManager.displays.isEmpty, "Detected at least one physical display")
        guard let firstDisplay = displayManager.displays.first else { return }

        TestRunner.assert(firstDisplay.id > 0, "Display has valid CGDirectDisplayID")
        TestRunner.assert(!firstDisplay.name.isEmpty, "Display has non-empty localized name")
        TestRunner.assert(!firstDisplay.resolutionDescription.isEmpty, "Display has non-empty resolution description")

        // Test DisplayMode & Settings serialization
        let originalMode = displayManager.settings.mode
        displayManager.setDisplayMode(.individual)
        TestRunner.assert(displayManager.settings.mode == .individual, "DisplayManager switches to individual mode")

        displayManager.setDisplayMode(.unified)
        TestRunner.assert(displayManager.settings.mode == .unified, "DisplayManager switches to unified mode")

        // Create synthetic video and test multi-display assignments
        let tempVideoURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("luma_disp_test.mp4")
        try? FileManager.default.removeItem(at: tempVideoURL)
        defer { try? FileManager.default.removeItem(at: tempVideoURL) }

        do {
            try await createSyntheticTestVideo(at: tempVideoURL)
            let item = WallpaperItem(name: "Multi-Display Wallpaper", fileURL: tempVideoURL)

            // Unified assignment
            displayManager.setUnifiedWallpaper(item: item)
            TestRunner.assert(displayManager.activeWallpaperId(for: firstDisplay.id) == item.id, "Unified wallpaper active on display")
            TestRunner.assert(displayManager.isAnyDisplayActive, "Reports isAnyDisplayActive == true")

            // Individual assignment
            let individualItem = WallpaperItem(name: "Individual Wallpaper", fileURL: tempVideoURL)
            displayManager.setDisplayMode(.individual)
            displayManager.setIndividualWallpaper(item: individualItem, for: firstDisplay.id)
            TestRunner.assert(displayManager.activeWallpaperId(for: firstDisplay.id) == individualItem.id, "Individual wallpaper active on display")

            // Stop wallpaper on display
            displayManager.stopWallpaper(for: firstDisplay.id)
            TestRunner.assert(displayManager.activeWallpaperId(for: firstDisplay.id) == nil, "Display assignment cleared after stop")

            displayManager.stopAll()
            TestRunner.assert(!displayManager.isAnyDisplayActive, "All displays stopped")
            displayManager.setDisplayMode(originalMode)
        } catch {
            TestRunner.assert(false, "Display manager test failed: \(error)")
        }
    }

    static func testPowerManagerAndEnergySettings() {
        let powerManager = PowerManager.shared

        // Test AppSettings defaults
        var settings = AppSettings()
        TestRunner.assert(settings.pauseOnDisplaySleep, "Default pauseOnDisplaySleep is true")
        TestRunner.assert(settings.pauseOnScreenLock, "Default pauseOnScreenLock is true")
        TestRunner.assert(settings.autoMuteAudio, "Default autoMuteAudio is true")
        TestRunner.assert(!settings.pauseOnBattery, "Default pauseOnBattery is false")

        powerManager.settings = settings

        // Test Display Sleep suspension
        powerManager.simulateDisplaySleep(true)
        TestRunner.assert(powerManager.isSuspended, "Suspended when display sleeps")

        powerManager.simulateDisplaySleep(false)
        TestRunner.assert(!powerManager.isSuspended, "Resumed when display wakes")

        // Test Screen Lock suspension
        powerManager.simulateScreenLock(true)
        TestRunner.assert(powerManager.isSuspended, "Suspended when screen is locked")

        powerManager.simulateScreenLock(false)
        TestRunner.assert(!powerManager.isSuspended, "Resumed when screen is unlocked")

        // Test Battery suspension when pauseOnBattery is enabled
        settings.pauseOnBattery = true
        powerManager.settings = settings

        powerManager.simulateBatteryState(true)
        TestRunner.assert(powerManager.isSuspended, "Suspended on battery when pauseOnBattery is enabled")

        powerManager.simulateBatteryState(false)
        TestRunner.assert(!powerManager.isSuspended, "Resumed on AC power")

        // Reset to default
        settings.pauseOnBattery = false
        powerManager.settings = settings
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

        await TestRunner.runSuite("WallpaperWindow Desktop Integration Tests") {
            testWallpaperWindowProperties()
        }

        await TestRunner.runSuite("WallpaperEngine Lifecycle Tests") {
            await testWallpaperEngineLifecycle()
        }

        await TestRunner.runSuite("LibraryStore Persistence Tests") {
            testLibraryStorePersistence()
        }

        await TestRunner.runSuite("WallpaperLibrary Operations Tests") {
            await testWallpaperLibraryOperations()
        }

        await TestRunner.runSuite("DisplayManager & Multi-Monitor Tests") {
            await testDisplayManagerAndConfigurations()
        }

        await TestRunner.runSuite("PowerManager & Energy Settings Tests") {
            testPowerManagerAndEnergySettings()
        }

        print("\n========================================")
        print("Results: \(TestRunner.passed) passed, \(TestRunner.failed) failed")
        print("========================================")

        if TestRunner.failed > 0 {
            exit(1)
        }
    }
}



