import SwiftUI
import AppKit
import LumaWallKit

struct MenuBarContentView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var library = WallpaperLibrary.shared
    @State private var displayManager = DisplayManager.shared
    @State private var powerManager = PowerManager.shared

    var body: some View {
        VStack {
            // Current Wallpaper Header
            if let active = library.activeDesktopWallpaper {
                Text("Current Wallpaper")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(active.name)
                    .font(.headline)

                if displayManager.isPlaying {
                    Text("● Playing (Looper Active)")
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else {
                    Text("⏸ Paused")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("LumaWall")
                    .font(.headline)
                Text("No Desktop Wallpaper Active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Playback Controls
            if displayManager.isAnyDisplayActive {
                Button {
                    displayManager.togglePlayPauseAll()
                } label: {
                    Label(displayManager.isPlaying ? "Pause Wallpaper" : "Play Wallpaper", systemImage: displayManager.isPlaying ? "pause.fill" : "play.fill")
                }

                Button {
                    displayManager.setMutedAll(!displayManager.isMuted)
                } label: {
                    Label(displayManager.isMuted ? "Unmute Audio" : "Mute Audio", systemImage: displayManager.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }

                Button(role: .destructive) {
                    library.stopDesktop()
                } label: {
                    Label("Stop Wallpaper", systemImage: "xmark.circle")
                }

                Divider()
            }

            // Change Wallpaper Submenu
            Menu {
                ForEach(library.wallpapers.filter { $0.isAvailable }) { item in
                    Button {
                        library.setAsDesktop(id: item.id)
                    } label: {
                        HStack {
                            Text(item.name)
                            if library.activeDesktopWallpaperId == item.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }

                if library.wallpapers.isEmpty {
                    Text("No wallpapers in library")
                }
            } label: {
                Label("Change Wallpaper", systemImage: "photo.on.rectangle")
            }

            // Displays Submenu
            Menu {
                Button {
                    displayManager.setDisplayMode(.unified)
                    library.persist()
                } label: {
                    HStack {
                        Text("Same on All Displays")
                        if displayManager.settings.mode == .unified {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                Button {
                    displayManager.setDisplayMode(.individual)
                    library.persist()
                } label: {
                    HStack {
                        Text("Individual per Display")
                        if displayManager.settings.mode == .individual {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                Divider()

                ForEach(displayManager.displays) { display in
                    let assignedId = displayManager.activeWallpaperId(for: display.id)
                    let assignedName = library.wallpapers.first(where: { $0.id == assignedId })?.name ?? "None"
                    Text("\(display.name): \(assignedName)")
                }
            } label: {
                Label("Displays", systemImage: "display.2")
            }

            Divider()

            // Application Open / Quit Actions
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
                AppCoordinator.shared.showMainWindow()
            } label: {
                Label("Open LumaWall…", systemImage: "sparkles.tv")
            }
            .keyboardShortcut("o")

            Divider()

            Button(role: .destructive) {
                AppCoordinator.shared.quit()
            } label: {
                Label("Quit LumaWall", systemImage: "power")
            }
            .keyboardShortcut("q")
        }
    }
}
