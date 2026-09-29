import SwiftUI
import AppKit
import LumaWallKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Enforce single instance: prevent duplicate processes and duplicate menu bar icons
        let myPID = ProcessInfo.processInfo.processIdentifier
        let bundleId = Bundle.main.bundleIdentifier ?? "com.lumawall.app"
        let runningInstances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            .filter { $0.processIdentifier != myPID }

        if let existingInstance = runningInstances.first {
            LumaLogger.app.info("Another LumaWall instance is already running (PID: \(existingInstance.processIdentifier)). Notifying it to open window.")
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.lumawall.app.show-window"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            existingInstance.activate()
            exit(0)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize high-level coordinator and restore wallpaper state
        AppCoordinator.shared.startup()

        let isBackground = CommandLine.arguments.contains("--background")
        if !isBackground {
            // Normal user launch (e.g. double-clicked app): show the wallpaper library window!
            DispatchQueue.main.async {
                MainWindowController.shared.showWindow()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindowController.shared.showWindow()
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            LumaLogger.app.info("Handling URL scheme: \(url.absoluteString)")
            if url.scheme == "lumawall" {
                MainWindowController.shared.showWindow()
                if url.host == "add-video" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        NotificationCenter.default.post(name: NSNotification.Name("com.lumawall.app.open-picker"), object: nil)
                    }
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
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
