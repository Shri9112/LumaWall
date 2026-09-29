import AppKit
import LumaWallKit

/// Native AppKit NSStatusItem manager providing 100% reliable Menu Bar interaction.
/// Bypasses SwiftUI MenuBarExtra bugs where accessory apps become unclickable.
@MainActor
public final class StatusItemManager: NSObject, NSMenuDelegate {
    public static let shared = StatusItemManager()

    private var statusItem: NSStatusItem?
    private let menu = NSMenu()

    public func setup() {
        guard statusItem == nil else { return }

        // Create standard variable-length status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            if let image = NSImage(systemSymbolName: "sparkles.tv", accessibilityDescription: "LumaWall")?.withSymbolConfiguration(config) {
                image.isTemplate = true
                button.image = image
            }
            button.toolTip = "LumaWall Live Wallpaper Engine"
        }

        menu.delegate = self
        statusItem?.menu = menu
        rebuildMenu()
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let library = WallpaperLibrary.shared

        // 1. Status Header
        if let active = library.activeDesktopWallpaper {
            let headerItem = NSMenuItem(title: "Wallpaper: \(active.name)", action: nil, keyEquivalent: "")
            headerItem.isEnabled = false
            menu.addItem(headerItem)

            let stateItem = NSMenuItem(title: "● Native (Desktop & Lock Screen)", action: nil, keyEquivalent: "")
            stateItem.isEnabled = false
            menu.addItem(stateItem)
        } else {
            let item = NSMenuItem(title: "LumaWall Ready", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        // 2. Quick Wallpaper Switcher Submenu
        let wallpapers = library.wallpapers.filter { $0.isAvailable }
        if !wallpapers.isEmpty {
            let changeMenu = NSMenu()
            for wallpaper in wallpapers {
                let item = NSMenuItem(title: wallpaper.name, action: #selector(selectWallpaper(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = wallpaper.id
                if library.activeDesktopWallpaperId == wallpaper.id {
                    item.state = .on
                }
                changeMenu.addItem(item)
            }

            let changeItem = NSMenuItem(title: "Change Wallpaper", action: nil, keyEquivalent: "")
            changeItem.image = NSImage(systemSymbolName: "photo.on.rectangle", accessibilityDescription: nil)
            changeItem.submenu = changeMenu
            menu.addItem(changeItem)

            menu.addItem(NSMenuItem.separator())
        }

        // 3. Open macOS System Settings > Wallpaper
        let settingsItem = NSMenuItem(title: "Open macOS Wallpaper Settings…", action: #selector(openSystemWallpaperSettings), keyEquivalent: ",")
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        settingsItem.target = self
        menu.addItem(settingsItem)

        // 4. Open LumaWall App Window
        let openItem = NSMenuItem(title: "Open Wallpaper Library…", action: #selector(openMainWindow), keyEquivalent: "o")
        openItem.image = NSImage(systemSymbolName: "sparkles.tv", accessibilityDescription: nil)
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        // 5. Quit
        let quitItem = NSMenuItem(title: "Quit LumaWall", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Actions

    @objc private func selectWallpaper(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        WallpaperLibrary.shared.setAsDesktop(id: id)
    }

    @objc private func openSystemWallpaperSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openMainWindow() {
        AppCoordinator.shared.showMainWindow()
    }

    @objc private func quitApp() {
        AppCoordinator.shared.quit()
    }
}
