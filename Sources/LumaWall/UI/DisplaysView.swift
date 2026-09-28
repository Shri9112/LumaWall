import SwiftUI
import AppKit
import LumaWallKit

struct DisplaysView: View {
    @State private var displayManager = DisplayManager.shared
    @State private var library = WallpaperLibrary.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Mode Selection Segmented Control
                    modeSelectorSection

                    Divider()

                    // Displays List / Grid
                    displaysListSection

                    Divider()

                    // Global Display Actions
                    globalControlsSection
                }
                .padding(24)
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            displayManager.refreshDisplays()
        }
    }

    // MARK: - Sections

    private var headerBar: some View {
        HStack {
            Image(systemName: "display.2")
                .font(.title2)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text("Displays")
                    .font(.headline)
                Text("\(displayManager.displays.count) Connected Display\(displayManager.displays.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private var modeSelectorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Display Mode")
                .font(.subheadline.weight(.semibold))

            Picker("Display Mode", selection: Binding(
                get: { displayManager.settings.mode },
                set: { newMode in
                    displayManager.setDisplayMode(newMode)
                    library.persist()
                }
            )) {
                ForEach(DisplayMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(displayManager.settings.mode.description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var displaysListSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Physical Displays")
                .font(.subheadline.weight(.semibold))

            ForEach(displayManager.displays) { display in
                displayCard(for: display)
            }
        }
    }

    private func displayCard(for display: DisplayInfo) -> some View {
        let assignedId = displayManager.activeWallpaperId(for: display.id)
        let assignedItem = library.wallpapers.first(where: { $0.id == assignedId })

        return HStack(spacing: 16) {
            // Display Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(width: 56, height: 56)

                Image(systemName: display.isMain ? "laptopcomputer" : "display")
                    .font(.title2)
                    .foregroundStyle(.tint)
            }

            // Display Details
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(display.name)
                        .font(.headline)

                    if display.isMain {
                        Text("Main Display")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                }

                Text("Resolution: \(display.resolutionDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let assignedItem {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("Wallpaper: \(assignedItem.name)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                    }
                    .padding(.top, 2)
                } else {
                    Text("No wallpaper assigned")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
            }

            Spacer()

            // Assignment Actions
            VStack(alignment: .trailing, spacing: 6) {
                Menu {
                    ForEach(library.wallpapers.filter { $0.isAvailable }) { item in
                        Button {
                            if displayManager.settings.mode == .individual {
                                displayManager.setIndividualWallpaper(item: item, for: display.id)
                            } else {
                                displayManager.setUnifiedWallpaper(item: item)
                            }
                            library.persist()
                        } label: {
                            HStack {
                                Text(item.name)
                                if item.id == assignedId {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }

                    if !library.wallpapers.isEmpty {
                        Divider()
                    }

                    Button(role: .destructive) {
                        displayManager.stopWallpaper(for: display.id)
                        library.persist()
                    } label: {
                        Text("Remove Wallpaper")
                    }
                } label: {
                    Label(assignedItem == nil ? "Assign Wallpaper…" : "Change…", systemImage: "sparkles.tv")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var globalControlsSection: some View {
        HStack(spacing: 12) {
            Button {
                displayManager.togglePlayPauseAll()
            } label: {
                Label(displayManager.isPlaying ? "Pause All" : "Resume All", systemImage: displayManager.isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.bordered)
            .disabled(!displayManager.isAnyDisplayActive)

            Button {
                displayManager.setMutedAll(!displayManager.isMuted)
            } label: {
                Label(displayManager.isMuted ? "Unmute All" : "Mute All", systemImage: displayManager.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .buttonStyle(.bordered)
            .disabled(!displayManager.isAnyDisplayActive)

            Spacer()

            Button(role: .destructive) {
                displayManager.stopAll()
                library.stopDesktop()
            } label: {
                Label("Stop All Displays", systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
            .disabled(!displayManager.isAnyDisplayActive)
        }
    }
}
