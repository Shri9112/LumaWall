# LumaWall

> **Native Apple Silicon Live Wallpaper Engine for macOS**

LumaWall is a fast, quiet, energy-efficient native macOS application that turns your local MP4, MOV, and M4V video files into animated desktop wallpapers.

Engineered from the ground up for Apple Silicon (M2 and newer), LumaWall renders high-resolution (1080p, 1440p, 4K, and 8K) looping video directly behind Finder desktop icons with near-zero CPU overhead.

---

## Features

- **Lock Screen Live Motion & Seamless Unlock Transition**: Bundled with a native macOS 26 `com.apple.wallpaper` ExtensionKit extension (`LumaWallWallpaperExtension.appex`) that renders live looping video on the Lock Screen and creates a 100% seamless, unbroken visual transition into the desktop when unlocking with Touch ID.
- **Zero-Glitch Color Synchronization**: Automatically updates macOS system desktop picture to match the active video's keyframe, eliminating Menu Bar header orange tinting when opening apps and stopping 3-finger swipe wallpaper flashes.
- **Behind Desktop Icons**: Renders strictly behind Finder icons, folders, and desktop widgets at the CoreGraphics desktop window level (`-2147483623`).
- **Full Interaction Pass-Through**: Mouse clicks, double-clicks, selection marquees, and right-click desktop menus pass completely through to Finder.
- **Never Steals Focus**: Keyboard focus and main window status remain strictly with your active applications.
- **100% Reliable Native Menu Bar Extra**: Uses AppKit `NSStatusItem` + `NSMenu` rather than SwiftUI `MenuBarExtra`, guaranteeing immediate click response with zero dropped events or freezes.
- **Hardware-Accelerated 4K/8K Playback**: Zero CPU frame copying. Apple Silicon's dedicated Media Engine (VideoToolbox) decodes directly to unified GPU memory.
- **Seamless Hardware Looping**: Built on `AVPlayerLooper` and `AVQueuePlayer` to eliminate black frames, audio pops, and stutter between loop cycles.
- **Multi-Monitor Flexibility**:
  - *Unified Mode*: Play the same live wallpaper across all connected displays.
  - *Individual Mode*: Assign distinct live wallpapers per physical screen (e.g. MacBook gets *Hogwarts.mp4*, external 4K monitor gets *Formula1.mp4*).
  - Handles dynamic connect, disconnect, resolution changes, and clamshell mode seamlessly.
- **Spaces & Mission Control Stability**: Uses AppKit collection behaviors (`.canJoinAllSpaces`, `.stationary`, `.ignoresCycle`, `.fullScreenAuxiliary`) to ensure wallpapers stay stationary during Exposé and persist across Spaces.
- **Event-Driven Energy Management**:
  - Automatically pauses when displays sleep.
  - Automatically pauses when the screen is locked.
  - Optional "Pause on Battery Power" mode (preserves 100% of MacBook battery).
  - Zero polling loops or background timers.
- **Zero-Copy Video Library**: Large 4K video files are never duplicated. Referenced in place via lightweight metadata caching and security-scoped bookmarks.
- **Continuous Background Daemon Support**: Can run as an independent launchd daemon starting automatically on boot with zero Dock clutter.
- **100% Offline & Private**: Zero network activity, zero telemetry, zero analytics, zero cloud accounts.

---

## Requirements & Compatibility

- **Target Architecture**: Apple Silicon (arm64 — M1, M2, M3, M4, and newer)
- **Supported macOS**: macOS 14.0 (Sonoma), macOS 15.0 (Sequoia), macOS 26.0+ (Tahoe / Darwin 25+)
- **Supported Formats**: MP4, MOV, M4V (H.264 / AVC, HEVC / H.265, Apple ProRes)
- **SIP Status**: Fully compatible with System Integrity Protection enabled. **Never disables SIP or Gatekeeper**.

---

## Architecture Overview

LumaWall combines low-level AppKit windowing with modern SwiftUI and AVFoundation:

```
┌────────────────────────────────────────────────────────────────────────┐
│                              LumaWall                                  │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│   ┌───────────────────────────┐      ┌─────────────────────────────┐   │
│   │   SwiftUI Management UI   │      │     NSStatusItem (Menu)     │   │
│   │  • Wallpaper Library Grid │      │  • Quick Play/Pause         │   │
│   │  • 4K Video Previewer     │      │  • Switch Active Wallpaper  │   │
│   │  • Display Assignments    │      │  • Open Manager / Quit      │   │
│   │  • Power/Battery Toggles  │      │                             │   │
│   └─────────────┬─────────────┘      └──────────────┬──────────────┘   │
│                 │                                   │                  │
│                 ▼                                   ▼                  │
│   ┌────────────────────────────────────────────────────────────────┐   │
│   │                     AppCoordinator / State                     │   │
│   │  • Manages Library, Settings, and Display Lifecycle            │   │
│   │  • Security-scoped bookmark persistence & local JSON cache     │   │
│   └─────────────────────────────┬──────────────────────────────────┘   │
│                                 │                                      │
│                                 ▼                                      │
│   ┌────────────────────────────────────────────────────────────────┐   │
│   │                    WallpaperDisplayManager                     │   │
│   │  • Observes screen connections (NSScreen parameters)           │   │
│   │  • Event-driven power observers (Sleep, Wake, Lock, Battery)   │   │
│   │  • One WallpaperWindowController per active physical screen    │   │
│   └─────────────────────────────┬──────────────────────────────────┘   │
│                                 │                                      │
│               ┌─────────────────┴─────────────────┐                    │
│               ▼                                   ▼                    │
│   ┌──────────────────────────┐        ┌──────────────────────────┐     │
│   │ WallpaperWindow (Screen 0)│       │ WallpaperWindow (Screen 1)│     │
│   │ • Level: desktopWindow   │        │ • Level: desktopWindow   │     │
│   │ • ignoresMouseEvents=true│        │ • ignoresMouseEvents=true│     │
│   │ • canJoinAllSpaces       │        │ • canJoinAllSpaces       │     │
│   │ • AVPlayerLayer (M2 HW)  │        │ • AVPlayerLayer (M2 HW)  │     │
│   └──────────────────────────┘        └──────────────────────────┘     │
└────────────────────────────────────────────────────────────────────────┘
```

For comprehensive technical specifications, see [ARCHITECTURE.md](ARCHITECTURE.md) and [PERFORMANCE.md](PERFORMANCE.md).

---

## 🛠️ Engineering Journey & Architecture Evolution

Building a live wallpaper application on modern macOS (Sonoma, Sequoia, and macOS 26) presents unique challenges due to macOS's strict WindowServer boundaries, App Sandbox, and the Lock Screen compositor.

LumaWall originally began using the traditional `NSWindow.Level.belowDesktop` floating window overlay hack. Through testing and user feedback, we discovered that floating windows cannot exist on the Lock Screen, resulting in frozen videos and desktop-lock screen desynchronization. 

We completely re-architected LumaWall by reverse-engineering Apple's internal `com.apple.wallpaper-extension` pipeline, enabling true native live motion under Finder and across the Lock Screen with zero overlay windows.

👉 **Read the full engineering deep-dive**: [ARCHITECTURE_EVOLUTION.md](ARCHITECTURE_EVOLUTION.md) — includes detailed postmortems on solving the Apple Settings `brk #0x1` trap, APFS zero-copy clones, and eliminating legacy menu bar clutter.

---

## Installation & Building from Source

### Prerequisites
- macOS 14.0 or newer running on Apple Silicon.
- Command Line Tools or Xcode with Swift 6.0+.

### Building with Swift Package Manager
```bash
# Clone or navigate to the repository
cd /path/to/Wallpaper

# Run the automated test suite (79 unit & integration tests)
swift run LumaWallTests

# Build debug binary
swift build --product LumaWall

# Run directly
swift run LumaWall
```

### Packaging Release `.app` Bundle
To build an optimized release binary and package `build/LumaWall.app`:
```bash
./Scripts/package_app.sh
```
The resulting application will be located at `build/LumaWall.app`.

### Running as a Continuous Background Daemon (Like MySQL / Docker)
If you want LumaWall to run permanently in the background without needing to manually open it, without cluttering your Dock (`LSUIElement = true`), and starting automatically on laptop boot/login:
```bash
# Install to /Applications and register as macOS LaunchAgent daemon
./Scripts/install_service.sh
```
To stop and uninstall the background service:
```bash
./Scripts/uninstall_service.sh
```

---

## Usage Guide

### 1. Adding Live Wallpapers
1. Launch LumaWall.
2. Click **[Add Wallpaper]** in the toolbar, or simply **drag and drop** your MP4/MOV video files anywhere onto the window.
3. LumaWall validates the video, extracts technical metadata (resolution, codec, duration, frame rate, file size), generates a sharp thumbnail, and adds it to your local library.

### 2. Setting as Desktop Wallpaper
1. Select any wallpaper in the library grid to open the live preview panel.
2. Click **[Set as Desktop Wallpaper]**.
3. The video immediately begins looping on your desktop behind your icons.
4. You can safely close the main window; the desktop wallpaper continues running smoothly in the background.

### 3. Managing Multiple Monitors
1. Click the **[Displays]** button in the main window toolbar or choose **Displays** from the menu bar.
2. Select your desired mode:
   - **Same on All Displays**: Unified playback across all screens.
   - **Individual per Display**: Click the assignment menu on each display card to assign specific wallpapers to specific screens.

### 4. Energy Management & Battery Settings
1. Click the **[Settings]** button in the main toolbar.
2. Configure your power preferences:
   - **Pause on Battery Power**: Toggle to automatically pause video playback when running on battery.
   - **Pause when Displays Sleep**: Halts GPU rendering when displays turn off.
   - **Pause when Screen is Locked**: Pauses playback while your Mac is locked.
   - **Pause during Fullscreen Applications**: Pauses when an app enters a fullscreen Space.

### 5. Menu Bar Controls
Click the `sparkles.tv` icon in your macOS menu bar to:
- See the currently playing wallpaper and playback state.
- Quickly Play / Pause playback.
- Mute / Unmute wallpaper audio.
- Switch to another wallpaper from the `Change Wallpaper` submenu.
- Open the main window or cleanly quit LumaWall.

---

## Known macOS Limitations

1. **WindowServer Level Ordering**:
   On macOS, third-party applications cannot draw *between* the Finder wallpaper and Finder desktop icons using public APIs other than `CGWindowLevelForKey(.desktopWindow)`. LumaWall uses this exact level, which sits at `-2147483623` (strictly below Finder's icons at `-2147483603`). This ensures desktop icons and widgets are always accessible.
2. **Third-Party Screen Savers**:
   macOS screen savers take precedence when the lock screen activates. LumaWall automatically pauses playback while the screen is locked to avoid competing for GPU resources with the screen saver.
3. **Stage Manager**:
   When Stage Manager is active, window thumbnails appear on the left screen edge. LumaWall renders behind both Stage Manager strips and desktop icons without interference.

---

## Privacy & Security

- **100% Offline**: No network requests are made. No analytics or crash telemetry.
- **Zero Elevated Privileges**: Runs strictly with standard user privileges. Does not require root or `sudo`.
- **System Integrity Protection**: Never modifies macOS system files or alters Gatekeeper settings.
- **Security-Scoped Bookmarks**: File access permissions are preserved securely across restarts using Apple's official sandbox-safe security-scoped bookmark APIs.

---

## License

This project is licensed under the MIT License.
