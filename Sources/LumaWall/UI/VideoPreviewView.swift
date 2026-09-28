import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers
import LumaWallKit

// MARK: - AppKit Player Host View

final class PlayerHostView: NSView {
    var playerLayer: AVPlayerLayer? {
        didSet {
            oldValue?.removeFromSuperlayer()
            if let playerLayer {
                layer?.addSublayer(playerLayer)
                playerLayer.frame = bounds
            }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer?.frame = bounds
        CATransaction.commit()
    }
}

struct PlayerLayerView: NSViewRepresentable {
    let playerLayer: AVPlayerLayer

    func makeNSView(context: Context) -> PlayerHostView {
        let view = PlayerHostView(frame: .zero)
        view.playerLayer = playerLayer
        return view
    }

    func updateNSView(_ nsView: PlayerHostView, context: Context) {
        if nsView.playerLayer !== playerLayer {
            nsView.playerLayer = playerLayer
        }
    }
}

// MARK: - Preview Player View

@MainActor
struct VideoPreviewView: View {
    @State private var player = WallpaperPlayer(isMuted: true)
    @State private var selectedURL: URL?
    @State private var metadata: VideoMetadata?
    @State private var isValidating = false
    @State private var errorMessage: String?
    @State private var isHoveringControls = false
    @State private var engine = WallpaperEngine.shared

    private let validator = VideoValidator()

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar

            Divider()

            // Main Content Area
            ZStack {
                Color(nsColor: .windowBackgroundColor)

                if let _ = selectedURL {
                    videoPlaybackArea
                } else {
                    emptyStateArea
                }
            }
            .frame(minHeight: 380)

            if selectedURL != nil {
                Divider()
                desktopControlBar
            }

            Divider()

            // Metadata and Controls Footer
            footerBar
        }
        .frame(minWidth: 720, minHeight: 560)
    }

    // MARK: - Subviews

    private var headerBar: some View {
        HStack {
            Image(systemName: "sparkles.tv.fill")
                .foregroundStyle(.tint)
                .font(.title2)

            VStack(alignment: .leading, spacing: 2) {
                Text("LumaWall")
                    .font(.headline)
                Text("Native Apple Silicon Live Wallpaper")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if engine.isDesktopActive {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                    Text("Desktop Wallpaper Running")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.12), in: Capsule())
                .padding(.trailing, 6)
            }

            if isValidating {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 8)
            }

            Button {
                selectVideoFile()
            } label: {
                Label("Choose Video…", systemImage: "plus.rectangle.on.folder")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var desktopControlBar: some View {
        HStack(spacing: 12) {
            let isCurrentDesktop = engine.isDesktopActive && engine.activeWallpaperURL == selectedURL

            if isCurrentDesktop {
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

                Button {
                    engine.togglePlayPause()
                } label: {
                    Label(engine.isPlaying ? "Pause Desktop" : "Resume Desktop", systemImage: engine.isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    engine.stopWallpaper()
                } label: {
                    Label("Stop Wallpaper", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedURL?.lastPathComponent ?? "Selected Video")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text("Ready to apply behind desktop icons")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    if let url = selectedURL {
                        engine.setWallpaper(url: url)
                    }
                } label: {
                    Label("Set as Desktop Wallpaper", systemImage: "sparkles.tv")
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThickMaterial)
    }

    private var videoPlaybackArea: some View {
        ZStack {
            PlayerLayerView(playerLayer: player.playerLayer)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
                .padding(16)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isHoveringControls = hovering
                    }
                }

            // Overlay Playback Controls on Hover
            if isHoveringControls || !player.isPlaying {
                VStack {
                    HStack {
                        Label("Hardware Looper Active", systemImage: "infinity.circle.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())
                            .foregroundStyle(.white)

                        Spacer()
                    }
                    .padding(28)

                    Spacer()

                    HStack(spacing: 20) {
                        Button {
                            player.togglePlayPause()
                        } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title)
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial, in: Circle())
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)

                        Button {
                            player.setMuted(!player.isMuted)
                        } label: {
                            Image(systemName: player.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.headline)
                                .frame(width: 36, height: 36)
                                .background(.ultraThinMaterial, in: Circle())
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)

                        if player.duration > 0 {
                            Text("\(formatSeconds(player.currentTime)) / \(formatSeconds(player.duration))")
                                .font(.caption.monospacedDigit())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.ultraThinMaterial, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(.bottom, 28)
                }
            }

            // Error Overlay
            if let error = errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)
                        .padding(.horizontal)
                }
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var emptyStateArea: some View {
        VStack(spacing: 16) {
            Image(systemName: "film.stack")
                .font(.system(size: 54))
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text("No Video Selected")
                    .font(.title3.weight(.medium))
                Text("Select an MP4, MOV, or M4V video to preview live hardware looping")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                selectVideoFile()
            } label: {
                Label("Browse Files", systemImage: "folder")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footerBar: some View {
        HStack(spacing: 16) {
            if let meta = metadata {
                Label(meta.resolutionDescription, systemImage: "tv")
                    .font(.caption)

                Divider()
                    .frame(height: 12)

                Label(meta.codec, systemImage: "gearshape.2")
                    .font(.caption)

                Divider()
                    .frame(height: 12)

                Label(meta.formattedFrameRate, systemImage: "speedometer")
                    .font(.caption)

                Divider()
                    .frame(height: 12)

                Label(meta.formattedFileSize, systemImage: "internaldrive")
                    .font(.caption)

                Divider()
                    .frame(height: 12)

                Label(meta.hasAudio ? "Audio track available" : "Silent video", systemImage: meta.hasAudio ? "waveform" : "speaker.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Supports Apple Silicon hardware decoding (H.264, HEVC 4K/8K)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if selectedURL != nil {
                Button("Clear") {
                    player.stop()
                    selectedURL = nil
                    metadata = nil
                    errorMessage = nil
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Actions

    private func selectVideoFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType.mpeg4Movie,
            UTType.quickTimeMovie,
            UTType.movie
        ]
        panel.message = "Choose an MP4 or MOV video file for LumaWall"
        panel.prompt = "Choose Video"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        loadVideo(url: url)
    }

    public func loadVideo(url: URL) {
        isValidating = true
        errorMessage = nil

        Task {
            do {
                let validatedMeta = try await validator.validate(url: url)
                self.metadata = validatedMeta
                self.selectedURL = url
                self.player.loadVideo(url: url, autoPlay: true)
                self.isValidating = false
            } catch {
                self.isValidating = false
                self.errorMessage = error.localizedDescription
                self.metadata = nil
                LumaLogger.video.error("Failed to validate video: \(error.localizedDescription)")
            }
        }
    }

    private func formatSeconds(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
