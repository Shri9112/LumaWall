import AppKit
import SwiftUI
import LumaWallKit

/// Manages the primary Wallpaper Library management window.
/// Provides reliable opening, centering, and hide-on-close behavior
/// suitable for both foreground and LSUIElement background daemon modes.
@MainActor
public final class MainWindowController: NSObject, NSWindowDelegate {
    public static let shared = MainWindowController()

    private var window: NSWindow?

    override private init() {
        super.init()
        setupDistributedObserver()
    }

    /// Brings the Wallpaper Library window to front, creating it if necessary.
    public func showWindow() {
        NSApp.activate(ignoringOtherApps: true)

        if let existing = window {
            if !existing.isVisible {
                existing.center()
            }
            existing.makeKeyAndOrderFront(nil)
            existing.orderFrontRegardless()
            return
        }

        // Create the primary management window
        let contentView = ContentView()
        let hostingController = NSHostingController(rootView: contentView)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "LumaWall — Live Wallpaper Library"
        newWindow.minSize = NSSize(width: 820, height: 520)
        newWindow.titlebarAppearsTransparent = false
        newWindow.titleVisibility = .visible
        newWindow.isReleasedWhenClosed = false
        newWindow.contentViewController = hostingController
        newWindow.center()
        newWindow.delegate = self

        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        newWindow.orderFrontRegardless()
    }

    /// Closes / hides the main window
    public func hideWindow() {
        window?.orderOut(nil)
    }

    // MARK: - NSWindowDelegate

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Intercept close button: hide window instead of destroying
        // so live wallpaper continues looping in background
        sender.orderOut(nil)
        return false
    }

    // MARK: - Inter-Process Notification Observer

    private func setupDistributedObserver() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.lumawall.app.show-window"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.showWindow()
            }
        }
    }
}
