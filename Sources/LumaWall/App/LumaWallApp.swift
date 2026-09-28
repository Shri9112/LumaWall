import SwiftUI
import AppKit
import LumaWallKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize native AppKit NSStatusItem
        StatusItemManager.shared.setup()

        if CommandLine.arguments.contains("--background") {
            DispatchQueue.main.async {
                for window in NSApp.windows where !(window is WallpaperWindow) {
                    window.orderOut(nil)
                }
            }
        }
    }
}

@main
struct LumaWallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        LumaLogger.app.info("LumaWall application initialized")
        AppCoordinator.shared.startup()
    }

    var body: some Scene {
        WindowGroup("LumaWall", id: "main") {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 960, height: 640)
    }
}
