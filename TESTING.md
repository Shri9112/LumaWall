# LumaWall Testing and Quality Assurance Guide

## 1. Overview

Testing a native macOS live wallpaper application requires a dual-track strategy:
1. **Automated Unit & Integration Tests**: Fast, deterministic testing of models, format validators, metadata parsers, thumbnail generation, atomic library persistence, multi-monitor configuration logic, and energy management state transitions.
2. **Manual & Interactive macOS QA Procedures**: Verification of AppKit window levels, WindowServer compositor integration, Mission Control animations, Spaces transitions, physical display hotplugging, and hardware sleep/wake lifecycles.

---

## 2. Automated Test Suite

The automated test suite runs via the native Swift test runner with zero third-party dependencies:

```bash
swift run LumaWallTests
```

### Test Coverage Breakdown (79 Tests)

| Suite | Focus Areas | Automated Assertions |
| :--- | :--- | :--- |
| **WallpaperItem Tests** | Model integrity, resolution descriptor classification, duration formatting, and file size representation. | 5 passed |
| **VideoMetadata Tests** | 4K UHD, 1440p QHD, 1080p FHD resolution classification, frame rate formatting, audio track presence. | 6 passed |
| **VideoValidator Rejection Tests** | Graceful rejection of missing files, non-video extensions (`.txt`), and empty files without crashing. | 2 passed |
| **End-to-End Synthetic Video Tests** | Programmatically synthesizes a real 1080p H.264 MP4 file via `AVAssetWriter`, verifies metadata extraction, and validates thumbnail JPEG disk creation. | 5 passed |
| **WallpaperWindow Desktop Integration Tests** | Verifies `level == .desktopWindow` (`-2147483623`), `ignoresMouseEvents == true`, `canBecomeKey == false`, `canBecomeMain == false`, `hasShadow == false`, `styleMask == .borderless`, and all four `collectionBehavior` flags (`.canJoinAllSpaces`, `.stationary`, `.ignoresCycle`, `.fullScreenAuxiliary`). | 10 passed |
| **WallpaperEngine Lifecycle Tests** | Verifies state machine transitions: idle -> setWallpaper -> play -> pause -> resume -> mute -> stop. | 10 passed |
| **LibraryStore Persistence Tests** | Tests atomic JSON serialization to disk, schema versioning, reload accuracy, and empty store handling. | 5 passed |
| **WallpaperLibrary Operations Tests** | Tests addition, selection, real-time search filtering, favorite toggling, desktop setting, and missing file resilience. | 13 passed |
| **DisplayManager & Multi-Monitor Tests** | Tests physical display discovery, `CGDirectDisplayID` validation, `.unified` vs `.individual` mode switching, per-display assignments, and teardown. | 11 passed |
| **PowerManager & Energy Settings Tests** | Tests default settings, simulated display sleep suspension, screen lock suspension, and battery power pause toggles. | 10 passed |
| **LoginItemManager Tests** | Tests `SMAppService` status reporting and graceful degradation across CLI vs packaged bundle environments. | 2 passed |

---

## 3. Practical Manual QA Checklist

Some macOS behaviors (such as physical display hotplugging or Finder icon drag-and-drop) must be verified on an actual Mac. Follow this checklist when testing a build:

### Checklist 1: Desktop Window Layer & Mouse Pass-Through
- [ ] **Desktop Icon Visibility**: Finder desktop icons, folders, and widgets remain 100% visible on top of the live wallpaper.
- [ ] **Single Click**: Single-clicking an empty area of the desktop focuses Finder and deselects other apps.
- [ ] **Double Click**: Double-clicking a desktop file or folder opens it in Finder as expected.
- [ ] **Drag Marquee**: Clicking and dragging across the desktop creates Finder's selection rectangle without interference.
- [ ] **Right-Click Context Menu**: Right-clicking the desktop opens Finder’s desktop menu (New Folder, Change Wallpaper, Sort By).
- [ ] **No Focus Stealing**: Clicking anywhere on the desktop does not cause LumaWall to steal keyboard focus.

### Checklist 2: Spaces, Mission Control & Fullscreen
- [ ] **Space Switching**: Switch between virtual desktops (Control + Left/Right Arrow or 3-finger swipe). The wallpaper remains steady and visible on every Space.
- [ ] **Mission Control (Exposé)**: Trigger Mission Control (Control + Up Arrow or 3-finger swipe up). The wallpaper remains stationary in the background and does not tile or fly away.
- [ ] **Fullscreen Applications**: Enter fullscreen mode in an app (e.g. Safari). The wallpaper remains clean beneath the application space and is not distorted when swiping back to Desktop.

### Checklist 3: Seamless Looping & Audio
- [ ] **Seamless Loop**: Observe the video looping. Ensure there is no black flash, freeze, or stutter between loop iterations.
- [ ] **Audio Mute Default**: Confirm that new wallpapers start with audio muted by default.
- [ ] **Audio Toggle**: Unmute audio in preview or settings; confirm clear audio playback without popping during loop seams.

### Checklist 4: Multi-Monitor Verification
- [ ] **Unified Mode**: Set a wallpaper in Unified Mode. Verify that both the MacBook display and external monitor play the wallpaper simultaneously.
- [ ] **Individual Mode**: Switch to Individual Mode in the Displays tab. Assign Wallpaper A to the MacBook screen and Wallpaper B to the external monitor. Confirm distinct video playback on each screen.
- [ ] **Hotplug Connect**: Plug in an external monitor while wallpaper is playing. Confirm the new monitor immediately loads the configured wallpaper.
- [ ] **Hotplug Disconnect**: Unplug the external monitor. Confirm playback on the MacBook continues smoothly and no orphaned windows remain.
- [ ] **Resolution Change**: Change display resolution in System Settings -> Displays. Confirm the wallpaper re-anchors to full screen without cropping or stretching.
- [ ] **Clamshell Mode**: With an external monitor and power connected, close the MacBook lid. Confirm the external monitor maintains full-screen live wallpaper playback.

### Checklist 5: Energy, Battery & Thermal Management
- [ ] **Display Sleep**: Allow the display to sleep (or press Control + Shift + Power/Eject). Check with `pmset -g` or Activity Monitor: GPU usage drops to 0%.
- [ ] **Display Wake**: Wake the display; playback resumes smoothly.
- [ ] **Screen Lock**: Press `Control + Command + Q` to lock the screen. Verify wallpaper pauses. Unlock the screen; verify playback resumes.
- [ ] **Pause on Battery**: In Settings, enable "Pause on Battery Power". Unplug the charger; confirm playback pauses and the menu bar status shows "Paused (Energy Saving)". Reconnect charger; playback automatically resumes.

### Checklist 6: Missing / Moved File Resilience
- [ ] Add an MP4 file to the library.
- [ ] In Finder, rename or move the MP4 file to another folder.
- [ ] Return to LumaWall: confirm the card displays the yellow `⚠ File Missing` badge and does NOT crash.
- [ ] Verify that clicking "Set as Desktop Wallpaper" is disabled and displays an explanatory message.

### Checklist 7: Menu Bar Companion & Graceful Exit
- [ ] **Menu Bar Icon**: Click the `sparkles.tv` icon in the menu bar. Verify current wallpaper title, Play/Pause, and Change Wallpaper submenus work.
- [ ] **Clean Quit**: Choose "Quit LumaWall" from the menu bar or press `Cmd + Q`. Confirm that all desktop windows close, video decoders terminate, and no zombie processes remain.
