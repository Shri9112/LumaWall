# LumaWall Architecture Documentation

## 1. Executive Summary

**LumaWall** is a native macOS live wallpaper application engineered specifically for Apple Silicon (M2 and newer). It enables users to display high-resolution (1080p, 1440p, 4K, and beyond) looping video files (MP4/MOV) as live desktop wallpapers. The engine runs natively, seamlessly placed behind desktop icons and normal application windows, with near-zero CPU overhead by leveraging hardware-accelerated video decoding via AVFoundation.

---

## 2. Evaluation of macOS Architectural Options

Before arriving at the chosen architecture, multiple macOS system mechanisms were thoroughly evaluated against the project requirements:

| Mechanism | Feasibility | Security / SIP | Spaces / Multi-Monitor | Verdict | Rationale |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **System Extension** | Incompatible | Requires Entitlements / SIP bypass | Not applicable | **Rejected** | System extensions (DriverKit, EndpointSecurity) execute in system space with no WindowServer context. Cannot render UI or manage display windows. |
| **App Extension** (ScreenSaver / Widget) | Incompatible | Sandboxed | Locked to Screensaver idle state | **Rejected** | macOS does not provide a public "Wallpaper Extension" point. Screen saver extensions only run when the machine is locked/idle, not behind active desktop icons during normal work. |
| **Daemon (launchd root)** | Incompatible | Root privileges | No Aqua session access | **Rejected** | Daemons do not have an Aqua GUI session and cannot talk to WindowServer or render AVPlayer layers. |
| **Pure SwiftUI Application** | Inadequate for Windowing | Public API | Limited window level control | **Partial** | SwiftUI `WindowGroup` cannot access `kCGDesktopWindowLevelKey`, configure `.ignoresMouseEvents`, or manage borderless full-screen layers across dynamic screen arrangements. However, SwiftUI is ideal for the Manager UI. |
| **AppKit Desktop Window + AVFoundation + SwiftUI UI** | **Optimal** | **100% Public APIs, SIP-safe, Sandboxing-compatible** | **Full support for Spaces, Mission Control, Multi-Display** | **SELECTED** | Provides precise control over `NSWindow.Level`, `collectionBehavior`, hardware-accelerated `AVPlayerLayer`, event-driven sleep/wake observation, and native SwiftUI management. |

---

## 3. Chosen Architecture: Hybrid AppKit Window Engine + AVFoundation + SwiftUI

```
┌────────────────────────────────────────────────────────────────────────┐
│                              LumaWall                                  │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│   ┌───────────────────────────┐      ┌─────────────────────────────┐   │
│   │   SwiftUI Management UI   │      │     NSStatusItem (Menu)     │   │
│   │  • Wallpaper Library      │      │  • Quick Play/Pause         │   │
│   │  • Video Previews         │      │  • Quick Switch Wallpaper   │   │
│   │  • Display Assignments    │      │  • Open Manager / Quit      │   │
│   │  • Power/Battery Settings │      │                             │   │
│   └─────────────┬─────────────┘      └──────────────┬──────────────┘   │
│                 │                                   │                  │
│                 ▼                                   ▼                  │
│   ┌────────────────────────────────────────────────────────────────┐   │
│   │                     AppCoordinator / State                     │   │
│   │  • Coordinates UI, Library, Settings, and WallpaperEngine      │   │
│   │  • Persists configuration to lightweight JSON store            │   │
│   └─────────────────────────────┬──────────────────────────────────┘   │
│                                 │                                      │
│                                 ▼                                      │
│   ┌────────────────────────────────────────────────────────────────┐   │
│   │                    WallpaperDisplayManager                     │   │
│   │  • Monitors screen connections / reconfigurations              │   │
│   │  • Manages 1 WallpaperWindowController per active NSScreen     │   │
│   │  • Power Management (Sleep/Wake/Lock/Battery event observers)  │   │
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

---

## 4. Deep Dive: Desktop Window Integration

### 4.1 Window Level Hierarchy in macOS
macOS assigns integer levels to windows managed by the WindowServer (`CoreGraphics` / `AppKit`). By querying `CGWindowLevelForKey`:

- **Desktop Window Level (`.desktopWindow`)**: `-2147483623`
- **Desktop Icon Window Level (`.desktopIconWindow`)**: `-2147483603`
- **Backstop Menu Level**: `-20`
- **Normal Application Level (`.normalWindow`)**: `0`
- **Floating Window Level (`.floatingWindow`)**: `3`

Notice that **Desktop Icon Window Level is 20 units above Desktop Window Level**.
Placing `WallpaperWindow` at:
```swift
self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
```
guarantees that:
1. The video renders **behind** all desktop icons, files, folders, and widgets.
2. The video renders **behind** all regular applications, menus, and popovers.
3. The video sits cleanly above the static system desktop image.

### 4.2 Non-Interactive & Pass-Through Behavior
To make the wallpaper window transparent to user interaction:
- `self.ignoresMouseEvents = true`: Any clicks, drags, marquee selections, double-clicks on desktop icons, and right-clicks pass through to Finder.
- `self.canBecomeKey = false` & `self.canBecomeMain = false`: The window never takes keyboard focus, preventing disruption to active apps.
- `self.hasShadow = false`: Eliminates unnecessary shadow generation in WindowServer.
- `self.styleMask = [.borderless]`: No title bar, buttons, or window frame.

### 4.3 Spaces & Mission Control Integration
When a user switches Spaces or triggers Mission Control:
```swift
self.collectionBehavior = [
    .canJoinAllSpaces,    // Visible across all virtual desktops / Spaces
    .stationary,          // Does not move or tile during Mission Control / Exposé
    .ignoresCycle,        // Excluded from Cmd+Tab and Cmd+` window cycling
    .fullScreenAuxiliary  // Persists across fullscreen application spaces
]
```

---

## 5. Hardware-Accelerated Video Playback (M2 Apple Silicon)

### 5.1 Playback Engine: `AVQueuePlayer` + `AVPlayerLooper`
- Rather than naive polling or resetting playhead time manually (which causes visible black glitches and stalls), LumaWall utilizes `AVPlayerLooper` with `AVQueuePlayer`.
- `AVPlayerLooper` pre-rolls and stitches loop cycles seamlessly at the CoreMedia layer.
- Zero CPU frame decoding: Hardware decoding is handled by Apple Silicon's dedicated Media Engine (VideoToolbox).
- `AVPlayerLayer` is added directly to the backing `CALayer` of the borderless window with `videoGravity = .resizeAspectFill`.

### 5.2 Audio Handling
- By default, live desktop wallpapers must be silent.
- The `AVPlayer` instance has `isMuted = true` and `volume = 0.0`.
- An optional user setting allows unmuting if desired.

---

## 6. Energy and Thermal Management

Continuous video playback on a laptop must be energy-conscious. LumaWall adopts a zero-polling, strictly event-driven observation model:

1. **System Sleep / Wake**:
   - `NSWorkspace.willSleepNotification` -> Pause all video players immediately.
   - `NSWorkspace.didWakeNotification` -> Resume playback gracefully.
2. **Display Sleep / Wake**:
   - `NSWorkspace.screensDidSleepNotification` -> Pause playback to stop GPU rendering.
   - `NSWorkspace.screensDidWakeNotification` -> Resume playback.
3. **Screen Lock**:
   - Monitored via distributed notification `com.apple.screenIsLocked` -> Pause playback.
   - `com.apple.screenIsUnlocked` -> Resume playback.
4. **Battery Power Awareness**:
   - Monitored using `IOPowerSources` / `IOPSCopyPowerSourcesInfo`. If the "Pause on Battery" setting is enabled, playback pauses when running on DC battery power.
5. **App Inactivity / Backgrounding**:
   - Closing the management UI does not terminate playback; closing the UI simply disposes of preview players, releasing unnecessary resources.

---

## 7. Multi-Display Strategy

- Multiple monitors are detected dynamically via `NSApplication.didChangeScreenParametersNotification`.
- Each display (`NSScreen`) is tracked by its unique display ID (`CGDirectDisplayID`).
- Each screen receives its own independent `WallpaperWindowController`.
- Supported configurations:
  - **Mirrored / Shared**: Same wallpaper played across all displays.
  - **Individual**: Specific wallpaper assigned to Screen A, another to Screen B.
- When displays disconnect or resolution changes, windows dynamically re-anchor to the updated screen bounds.

---

## 8. Persistence & Metadata Architecture

- Wallpapers are referenced by file URL (security-scoped bookmark where applicable). The application never duplicates large 4K video files.
- Metadata (duration, resolution, codec, file size, thumbnail cache path) is stored locally in lightweight JSON (`Application Support/LumaWall/library.json`).
- Thumbnails are generated asynchronously via `AVAssetImageGenerator` and cached on disk.

---

## 9. Launch at Login

- Uses Apple's official `SMAppService.mainApp` API (macOS 13+).
- Requires zero fragile launch scripts in `~/Library/LaunchAgents/`.
- Reflects real-time service status (`.enabled`, `.notRegistered`, `.requiresApproval`).

---

## 10. Summary of APIs

### Selected APIs
- `AppKit` (`NSWindow`, `NSScreen`, `NSApplication`, `NSStatusItem`)
- `AVFoundation` (`AVQueuePlayer`, `AVPlayerLooper`, `AVPlayerLayer`, `AVAsset`, `AVAssetImageGenerator`)
- `CoreGraphics` (`CGWindowLevelForKey(.desktopWindow)`)
- `ServiceManagement` (`SMAppService`)
- `OSLog` (`Logger(subsystem:category:)`)
- `SwiftUI` (Control Panel UI, Settings, Library Grid)

### Rejected APIs
- Private CGS/SkyLight window APIs (`CGSSetWindowLevel`, etc.) — *Unnecessary and prone to breaking across macOS updates; official CoreGraphics levels work perfectly.*
- `VLCKit` / `FFmpeg` — *Heavyweight, lack direct Apple Silicon zero-copy CALayer integration, large binary size.*
- `ScreenSaver` framework for wallpaper — *Only activates on screen lock, cannot run behind active desktop.*
- Cron / Timer polling — *Replaced with event-driven notifications.*
