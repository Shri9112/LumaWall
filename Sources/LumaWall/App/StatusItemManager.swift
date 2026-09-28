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
        let displayManager = DisplayManager.shared

        // 1. Status Header
        if let active = library.activeDesktopWallpaper {
            let headerItem = NSMenuItem(title: "Wallpaper: \(active.name)", action: nil, keyEquivalent: "")
            headerItem.isEnabled = false
            menu.addItem(headerItem)

            let stateText = displayManager.isPlaying ? "● Looping (M2 Hardware Accelerated)" : "⏸ Paused"
            let stateItem = NSMenuItem(title: stateText, action: nil, keyEquivalent: "")
            stateItem.isEnabled = false
            menu.addItem(stateItem)
        } else {
            let item = NSMenuItem(title: "LumaWall — Inactive", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        // 2. Playback Controls
        if displayManager.isAnyDisplayActive {
            let playPauseTitle = displayManager.isPlaying ? "Pause Wallpaper" : "Play Wallpaper"
            let playPauseItem = NSMenuItem(title: playPauseTitle, action: #selector(togglePlayPause), keyEquivalent: "p")
            playPauseItem.target = self
            menu.addItem(playPauseItem)

            let muteTitle = displayManager.isMuted ? "Unmute Audio" : "Mute Audio"
            let muteItem = NSMenuItem(title: muteTitle, action: #selector(toggleMute), keyEquivalent: "m")
            muteItem.target = self
            menu.addItem(muteItem)

            let stopItem = NSMenuItem(title: "Stop Wallpaper", action: #selector(stopWallpaper), keyEquivalent: "s")
            stopItem.target = self
            menu.addItem(stopItem)

            menu.addItem(NSMenuItem.separator())
        }

        // 3. Quick Wallpaper Switcher Submenu
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
            changeItem.submenu = changeMenu
            menu.addItem(changeItem)
        }

        // 4. Displays Submenu
        let displaysMenu = NSMenu()
        let unifiedItem = NSMenuItem(title: "Same on All Displays", action: #selector(setUnifiedMode), keyEquivalent: "")
        unifiedItem.target = self
        if displayManager.settings.mode == .unified { unifiedItem.state = .on }
        displaysMenu.addItem(unifiedItem)

        let individualItem = NSMenuItem(title: "Individual per Display", action: #selector(setIndividualMode), keyEquivalent: "")
        individualItem.target = self
        if displayManager.settings.mode == .individual { individualItem.state = .on }
        displaysMenu.addItem(individualItem)

        let displaysItem = NSMenuItem(title: "Displays", action: nil, keyEquivalent: "")
        displaysItem.submenu = displaysMenu
        menu.addItem(displaysItem)

        menu.addItem(NSMenuItem.separator())

        // 5. Open App Window
        let openItem = NSMenuItem(title: "Open Wallpaper Library…", action: #selector(openMainWindow), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        // 6. Quit
        let quitItem = NSMenuItem(title: "Quit LumaWall", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Actions

    @objc private func togglePlayPause() {
        DisplayManager.shared.togglePlayPauseAll()
    }

    @objc private func toggleMute() {
        let isMuted = DisplayManager.shared.isMuted
        DisplayManager.shared.setMutedAll(!isMuted)
    }

    @objc private func stopWallpaper() {
        WallpaperLibrary.shared.stopDesktop()
    }

    @objc private func selectWallpaper(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        WallpaperLibrary.shared.setAsDesktop(id: id)
    }

    @objc private func setUnifiedMode() {
        DisplayManager.shared.setDisplayMode(.unified)
        WallpaperLibrary.shared.persist()
    }

    @objc private func setIndividualMode() {
        DisplayManager.shared.setDisplayMode(.individual)
        WallpaperLibrary.shared.persist()
    }

    @objc private func openMainWindow() {
        AppCoordinator.shared.showMainWindow()
    }

    @objc private func quitApp() {
        AppCoordinator.shared.quit()
    }
}
