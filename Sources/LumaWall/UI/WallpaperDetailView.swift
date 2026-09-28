import SwiftUI
import AppKit
import LumaWallKit

struct WallpaperDetailView: View {
    let item: WallpaperItem
    let isActiveOnDesktop: Bool
    let onSetAsDesktop: () -> Void
    let onStopDesktop: () -> Void
    let onToggleFavorite: () -> Void
    let onRemove: () -> Void

    @State private var previewPlayer = WallpaperPlayer(isMuted: true)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Live Video Preview
                previewSection

                // Missing File Banner if applicable
                if !item.isAvailable {
                    missingFileBanner
                }

                // Title and Primary Actions
                headerSection

                Divider()

                // Metadata Cards Grid
                metadataSection

                Divider()

                // File Path and Management Actions
                actionsSection
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            loadPreview()
        }
        .onChange(of: item.id) { _, _ in
            loadPreview()
        }
    }

    // MARK: - Sections

    private var previewSection: some View {
        ZStack {
            if item.isAvailable {
                PlayerLayerView(playerLayer: previewPlayer.playerLayer)
                    .aspectRatio(16/9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 5)

                // Overlay Controls
                VStack {
                    HStack {
                        Label("Preview", systemImage: "eye.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                            .foregroundStyle(.white)

                        Spacer()

                        Button {
                            previewPlayer.setMuted(!previewPlayer.isMuted)
                        } label: {
                            Image(systemName: previewPlayer.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(6)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)

                    Spacer()

                    HStack {
                        Button {
                            previewPlayer.togglePlayPause()
                        } label: {
                            Image(systemName: previewPlayer.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Text("\(formatSeconds(previewPlayer.currentTime)) / \(formatSeconds(item.duration))")
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .padding(12)
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.5))
                        .aspectRatio(16/9, contentMode: .fit)

                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.yellow)
                        Text("Video File Unavailable")
                            .font(.headline)
                        Text("The original file was moved, renamed, or deleted.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var missingFileBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("File Missing on Disk")
                    .font(.subheadline.weight(.semibold))
                Text("Path: \(item.fileURL.path(percentEncoded: false))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(12)
        .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)

                    Text(item.fileURL.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    onToggleFavorite()
                } label: {
                    Image(systemName: item.isFavorite ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundStyle(item.isFavorite ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
            }

            // Desktop Status & Main Action
            if isActiveOnDesktop {
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Active on Desktop")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.12), in: Capsule())

                    Spacer()

                    Button(role: .destructive) {
                        onStopDesktop()
                    } label: {
                        Label("Stop Wallpaper", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            } else {
                Button {
                    onSetAsDesktop()
                } label: {
                    Label("Set as Desktop Wallpaper", systemImage: "sparkles.tv")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!item.isAvailable)
            }
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Specifications")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                metaItem(title: "Resolution", value: item.resolutionDescription, icon: "tv")
                metaItem(title: "Codec", value: item.codec ?? "Unknown", icon: "gearshape.2")
                metaItem(title: "Duration", value: item.formattedDuration, icon: "clock")
                metaItem(title: "File Size", value: item.formattedFileSize, icon: "internaldrive")
            }
        }
    }

    private func metaItem(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("File Location")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(item.fileURL.path(percentEncoded: false))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))

            HStack {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(!item.isAvailable)

                Spacer()

                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Label("Remove from Library", systemImage: "trash")
                }
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Helpers

    private func loadPreview() {
        if item.isAvailable {
            previewPlayer.loadVideo(url: item.fileURL, autoPlay: true)
        } else {
            previewPlayer.stop()
        }
    }

    private func formatSeconds(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
