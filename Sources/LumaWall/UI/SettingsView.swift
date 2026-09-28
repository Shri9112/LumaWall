import SwiftUI
import AppKit
import LumaWallKit

struct SettingsView: View {
    @State private var powerManager = PowerManager.shared
    @State private var library = WallpaperLibrary.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    // Current Power State Live Card
                    powerStatusCard

                    Divider()

                    // Energy & Battery Settings
                    energySettingsSection

                    Divider()

                    // Playback & Audio Settings
                    playbackSettingsSection

                    Divider()

                    // General Settings
                    generalSettingsSection
                }
                .padding(24)
            }
        }
        .frame(minWidth: 540, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Sections

    private var headerBar: some View {
        HStack {
            Image(systemName: "gearshape.2.fill")
                .font(.title2)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text("Settings")
                    .font(.headline)
                Text("Energy Management & Preferences")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private var powerStatusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("System & Energy Status")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                statusPill(
                    title: "Power Source",
                    value: powerManager.isOnBattery ? "Battery Power" : "Power Adapter (AC)",
                    icon: powerManager.isOnBattery ? "battery.75" : "bolt.fill",
                    color: powerManager.isOnBattery ? .orange : .green
                )

                statusPill(
                    title: "Hardware Engine",
                    value: "Apple Silicon M2",
                    icon: "cpu.fill",
                    color: .blue
                )

                statusPill(
                    title: "Wallpaper Engine",
                    value: powerManager.isSuspended ? "Paused (Energy Saving)" : "Active",
                    icon: powerManager.isSuspended ? "pause.circle.fill" : "play.circle.fill",
                    color: powerManager.isSuspended ? .yellow : .green
                )
            }
        }
    }

    private func statusPill(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var energySettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Battery & Energy Management")
                .font(.subheadline.weight(.semibold))

            Toggle(isOn: Binding(
                get: { powerManager.settings.pauseOnBattery },
                set: { val in
                    powerManager.settings.pauseOnBattery = val
                    library.persist()
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pause on Battery Power")
                        .font(.body)
                    Text("Automatically pause live video playback when running on battery to maximize MacBook battery life.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: Binding(
                get: { powerManager.settings.pauseOnDisplaySleep },
                set: { val in
                    powerManager.settings.pauseOnDisplaySleep = val
                    library.persist()
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pause when Displays Sleep")
                        .font(.body)
                    Text("Stops GPU decoding immediately when screens turn off.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: Binding(
                get: { powerManager.settings.pauseOnScreenLock },
                set: { val in
                    powerManager.settings.pauseOnScreenLock = val
                    library.persist()
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pause when Screen is Locked")
                        .font(.body)
                    Text("Halts playback while the Mac is locked.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: Binding(
                get: { powerManager.settings.pauseOnFullscreen },
                set: { val in
                    powerManager.settings.pauseOnFullscreen = val
                    library.persist()
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pause during Fullscreen Applications")
                        .font(.body)
                    Text("Pauses playback while using an application in fullscreen Space.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var playbackSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Audio & Looping")
                .font(.subheadline.weight(.semibold))

            Toggle(isOn: Binding(
                get: { powerManager.settings.autoMuteAudio },
                set: { val in
                    powerManager.settings.autoMuteAudio = val
                    library.persist()
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mute Audio by Default")
                        .font(.body)
                    Text("Live wallpapers run silently by default. Can be toggled per wallpaper.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var generalSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("General")
                .font(.subheadline.weight(.semibold))

            Toggle(isOn: Binding(
                get: { powerManager.settings.autoStartOnLaunch },
                set: { val in
                    powerManager.settings.autoStartOnLaunch = val
                    library.persist()
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start Wallpaper Automatically on App Launch")
                        .font(.body)
                    Text("Restores last active desktop wallpaper when LumaWall starts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
