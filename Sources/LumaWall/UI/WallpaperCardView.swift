import SwiftUI
import AppKit
import LumaWallKit

struct WallpaperCardView: View {
    let item: WallpaperItem
    let isSelected: Bool
    let isActiveOnDesktop: Bool
    let onSelect: () -> Void
    let onSetAsDesktop: () -> Void
    let onToggleFavorite: () -> Void
    let onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail Area
            ZStack(alignment: .topTrailing) {
                thumbnailImage
                    .frame(height: 140)
                    .clipped()

                // Resolution Badge (Top Left)
                HStack {
                    Text(item.resolutionDescription.components(separatedBy: " ").first ?? "HD")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.white)

                    Spacer()

                    // Favorite Button (Top Right)
                    Button {
                        onToggleFavorite()
                    } label: {
                        Image(systemName: item.isFavorite ? "star.fill" : "star")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(item.isFavorite ? .yellow : .white.opacity(0.8))
                            .padding(6)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)

                // Status Indicators (Bottom Overlays)
                VStack {
                    Spacer()
                    HStack {
                        if isActiveOnDesktop {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)
                                Text("On Desktop")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.green)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.7), in: Capsule())
                        } else if !item.isAvailable {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.yellow)
                                Text("File Missing")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.yellow)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.7), in: Capsule())
                        }

                        Spacer()

                        Text(item.formattedDuration)
                            .font(.system(size: 10, weight: .medium).monospacedDigit())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(.white)
                    }
                    .padding(8)
                }
            }

            // Info Bar
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                HStack {
                    Text(item.codec ?? "Video")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Text(item.formattedFileSize)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor : (isHovering ? Color.secondary.opacity(0.3) : Color.white.opacity(0.08)),
                    lineWidth: isSelected ? 2.5 : 1
                )
        )
        .shadow(color: isSelected ? Color.accentColor.opacity(0.25) : Color.black.opacity(0.12), radius: isSelected ? 8 : 4, y: 2)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .contextMenu {
            Button {
                onSetAsDesktop()
            } label: {
                Label("Set as Desktop Wallpaper", systemImage: "sparkles.tv")
            }
            .disabled(!item.isAvailable)

            Button {
                onToggleFavorite()
            } label: {
                Label(item.isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: item.isFavorite ? "star.slash" : "star")
            }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }

            Divider()

            Button(role: .destructive) {
                onRemove()
            } label: {
                Label("Remove from Library", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var thumbnailImage: some View {
        if let thumbURL = item.thumbnailURL, let nsImage = NSImage(contentsOf: thumbURL) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Color.black.opacity(0.6)
                Image(systemName: "film")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
