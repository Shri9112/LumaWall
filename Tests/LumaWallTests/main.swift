import Foundation
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

    static func runSuite(_ name: String, tests: () throws -> Void) {
        print("\n🧪 Running Suite: \(name)")
        do {
            try tests()
        } catch {
            failed += 1
            print("  ✗ Suite error: \(error)")
        }
    }
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

    static func main() {
        print("========================================")
        print("  LumaWall Automated Test Suite")
        print("========================================")

        TestRunner.runSuite("WallpaperItem Tests") {
            testWallpaperItemInitialization()
        }

        print("\n========================================")
        print("Results: \(TestRunner.passed) passed, \(TestRunner.failed) failed")
        print("========================================")

        if TestRunner.failed > 0 {
            exit(1)
        }
    }
}
