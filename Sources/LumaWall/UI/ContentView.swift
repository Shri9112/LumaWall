import SwiftUI
import AppKit
import UniformTypeIdentifiers
import LumaWallKit

struct ContentView: View {
    @State private var library = WallpaperLibrary.shared
    @State private var isImporting = false
    @State private var importErrorMessage: String?
    @State private var showErrorAlert = false

    private let gridColumns = [
        GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 16)
    ]

    var body: some View {
        NavigationSplitView {
            // Main Library Grid Area
            VStack(spacing: 0) {
                // Filter & Search Bar
                filterAndSearchBar

                Divider()

                // Wallpaper Grid Content
                if library.wallpapers.isEmpty {
                    emptyLibraryState
                } else if library.filteredWallpapers.isEmpty {
                    emptySearchState
                } else {
                    wallpaperGridView
                }
            }
            .navigationSplitViewColumnWidth(min: 440, ideal: 560)
        } detail: {
            // Detail Inspector Area
            if let selected = library.selectedWallpaper {
                WallpaperDetailView(
                    item: selected,
                    isActiveOnDesktop: library.activeDesktopWallpaperId == selected.id,
                    onSetAsDesktop: {
                        library.setAsDesktop(id: selected.id)
                    },
                    onStopDesktop: {
                        library.stopDesktop()
                    },
                    onToggleFavorite: {
                        library.toggleFavorite(id: selected.id)
                    },
                    onRemove: {
                        library.removeWallpaper(id: selected.id)
                    }
                )
            } else {
                emptySelectionState
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles.tv.fill")
                        .foregroundStyle(.tint)
                        .font(.title3)

                    Text("LumaWall")
                        .font(.headline.weight(.bold))
                }
            }

            ToolbarItem(placement: .status) {
                if let active = library.activeDesktopWallpaper {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                        Text("Desktop: \(active.name)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.12), in: Capsule())
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    openFilePicker()
                } label: {
                    Label("Add Wallpaper", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .alert("Import Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importErrorMessage ?? "An unknown error occurred while importing video.")
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
    }

    // MARK: - Subviews

    private var filterAndSearchBar: some View {
        HStack(spacing: 12) {
            // Search Field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search wallpapers…", text: $library.searchText)
                    .textFieldStyle(.plain)
                if !library.searchText.isEmpty {
                    Button {
                        library.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))

            // Favorites Filter Toggle
            Button {
                library.filterFavoritesOnly.toggle()
            } label: {
                Image(systemName: library.filterFavoritesOnly ? "star.fill" : "star")
                    .foregroundStyle(library.filterFavoritesOnly ? .yellow : .secondary)
            }
            .buttonStyle(.bordered)
            .help("Show Favorites Only")

            if isImporting {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var wallpaperGridView: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(library.filteredWallpapers) { item in
                    WallpaperCardView(
                        item: item,
                        isSelected: library.selectedWallpaperId == item.id,
                        isActiveOnDesktop: library.activeDesktopWallpaperId == item.id,
                        onSelect: {
                            library.selectedWallpaperId = item.id
                        },
                        onSetAsDesktop: {
                            library.setAsDesktop(id: item.id)
                        },
                        onToggleFavorite: {
                            library.toggleFavorite(id: item.id)
                        },
                        onRemove: {
                            library.removeWallpaper(id: item.id)
                        }
                    )
                }
            }
            .padding(16)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var emptyLibraryState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles.tv")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("No Live Wallpapers Added")
                    .font(.title2.weight(.semibold))

                Text("Add your own 4K MP4 or MOV video files to start creating live wallpapers.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            Button {
                openFilePicker()
            } label: {
                Label("Add Your First Wallpaper", systemImage: "plus.rectangle.on.folder")
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("Or drag and drop video files anywhere into this window")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private var emptySearchState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text("No Wallpapers Match Search")
                .font(.headline)

            Button("Clear Filters") {
                library.searchText = ""
                library.filterFavoritesOnly = false
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private var emptySelectionState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Select a Wallpaper")
                .font(.headline)

            Text("Choose a wallpaper from the library to preview and set on your desktop.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [
            UTType.mpeg4Movie,
            UTType.quickTimeMovie,
            UTType.movie
        ]
        panel.message = "Choose MP4 or MOV video files to add to LumaWall Library"
        panel.prompt = "Add to Library"

        guard panel.runModal() == .OK else { return }

        let urls = panel.urls
        Task {
            await importVideos(urls: urls)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

                    let ext = url.pathExtension.lowercased()
                    if VideoValidator.supportedExtensions.contains(ext) {
                        Task { @MainActor in
                            await self.importVideos(urls: [url])
                        }
                    }
                }
            }
        }
        return handled
    }

    private func importVideos(urls: [URL]) async {
        isImporting = true
        for url in urls {
            do {
                try await library.addWallpaper(from: url)
            } catch {
                importErrorMessage = error.localizedDescription
                showErrorAlert = true
                LumaLogger.library.error("Import failed for \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        isImporting = false
    }
}
