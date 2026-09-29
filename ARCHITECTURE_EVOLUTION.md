# Architectural Evolution & Engineering Roadblocks

This document details the engineering journey of **LumaWall**, the real-world obstacles encountered while developing live wallpaper engines on modern macOS (Sonoma, Sequoia, and macOS 26), and how the architecture evolved from a legacy floating overlay hack to a fully native Apple ExtensionKit engine.

---

## 1. The Challenge: Why macOS Live Wallpapers Are Hard

Unlike Windows or Linux (where background windows can be arbitrarily pinned to desktop surfaces), modern macOS enforces strict security boundaries, isolated WindowServer spaces, and distinct compositor contexts:

1. **The Aqua Workspace Boundary**: User applications run in Aqua. The macOS Desktop, Finder icons, and the Lock Screen are managed by isolated system daemons (`Finder`, `loginwindow`, `WallpaperAgent`).
2. **The Lock Screen Wall**: User windows (even borderless AppKit windows at `.desktopWindow` level) **cannot exist** on the Lock Screen or Screen Saver layer.
3. **Multi-Space Transitions**: 3-finger trackpad gestures to switch Spaces animate desktop windows away from the physical display surface.

---

## 2. Phase 1: The Legacy Floating Window Engine (And Why It Failed)

In early development, LumaWall utilized the traditional technique common to legacy Mac wallpaper utilities: an invisible borderless `NSWindow` pinned at `kCGDesktopWindowLevelKey` (`NSWindow.Level.belowDesktop`) hosting an `AVPlayerLayer`.

```
[ Traditional Floating Overlay Approach - Legacy ]
┌──────────────────────────────────────────────┐
│  Desktop Icons (Finder)                      │
├──────────────────────────────────────────────┤
│  LumaWall NSWindow (Level: belowDesktop)     │  <-- Invisible floating window
├──────────────────────────────────────────────┤
│  Native macOS System Wallpaper (Static)      │
└──────────────────────────────────────────────┘
```

### Critical Flaws Discovered in Phase 1:

- ❌ **Lock Screen Freeze & Reversion**: When the user locks their Mac or puts it to sleep, macOS disables user space window compositing. The floating window was suppressed, exposing the underlying static Apple wallpaper. When unlocking, the video would stutter or freeze.
- ❌ **Desktop vs. Lock Screen Desynchronization**: Changing the wallpaper inside the app updated the floating window, but the Lock Screen still showed the previously configured macOS wallpaper, creating a jarring mismatch.
- ❌ **Mission Control & Spaces Artifacts**: Swiping across Spaces caused the floating window to visibly lag behind the system wallpaper layer.
- ❌ **Menu Bar Clutter & Manual Controls**: The menu bar had to provide manual `Pause`, `Resume`, `Mute`, and `Stop` buttons because macOS had no knowledge that a video was playing.

---

## 3. Phase 2: Reverse-Engineering Apple's Native `WallpaperAgent` Pipeline

To achieve the seamless desktop-to-lock-screen transition seen in Apple's built-in aerial wallpapers, we investigated Apple's internal wallpaper architecture introduced in macOS Sonoma.

We discovered that macOS renders live motion through an internal ExtensionKit extension point:
```
com.apple.wallpaper-extension
```

We completely re-architected LumaWall by creating a sandboxed companion extension:
`LumaWallWallpaperExtension.appex`.

```
[ Modern Native Pipeline - LumaWall v2.0 ]
┌────────────────────────────────────────────────────────┐
│                   macOS WindowServer                   │
├────────────────────────────────────────────────────────┤
│                 Desktop Icons (Finder)                 │
├────────────────────────────────────────────────────────┤
│                   WallpaperAgent.app                   │
│  ┌──────────────────────────────────────────────────┐  │
│  │     LumaWallWallpaperExtension.appex (Sandboxed) │  │
│  │   • Metal & AVFoundation Hardware Decoder        │  │
│  │   • Renders directly under Finder & Lock Screen  │  │
│  └──────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────┘
```

### Engineering Roadblocks Encountered & Solutions:

#### 1. The System Settings Crash Trap (`brk #0x1` Trap)
- **The Problem**: When listing custom user wallpapers in macOS System Settings > Wallpaper, items marked with `disposability: .removable` displayed an "X" delete badge. Clicking the "X" caused Apple's `Wallpaper.appex` SwiftUI view to trap with an unhandled exception (`brk #0x1` at `0x10008fbf8`), crashing System Settings. Apple's internal code attempted to call proprietary iCloud delete handlers that fail on non-Apple items.
- **The Solution**: We changed `disposability` to `.none` in `SettingsProvider.swift`. Deletion and library management are cleanly handled inside the LumaWall app, stabilizing System Settings 100%.

#### 2. Direct Wallpaper Activation via `Index.plist`
- **The Problem**: macOS provides no public API to programmatically command `WallpaperAgent` to switch extension wallpapers.
- **The Solution**: We engineered `VideoDeploymentService.applyToSystemWallpaper(entryID:)`. It safely updates Apple's `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist` for `Desktop`, `Linked`, and `Idle` surfaces, and triggers an instantaneous daemon restart via `killall WallpaperAgent`. Both Desktop and Lock Screen switch immediately and stay synchronized.

#### 3. Zero-Copy Storage with APFS Copy-on-Write Clones
- **The Problem**: 4K video wallpapers are large (500 MB to 2 GB). Copying a file from the user's Downloads folder into the sandboxed extension container doubled disk consumption and introduced import lag.
- **The Solution**: Implemented native APFS clone semantics using Darwin's `copyfile(url.path, destURL.path, nil, copyfile_flags_t(COPYFILE_CLONE | COPYFILE_DATA))`. This enables sub-millisecond imports (< 0.01s) with **0 MB duplicate disk space**.

#### 4. Instant Keyframe Thumbnail Generation
- **The Problem**: Generating video preview thumbnails by decoding from time zero resulted in perceptible latency when adding batches of 4K videos.
- **The Solution**: Configured `AVAssetImageGenerator` with infinite time tolerances (`.positiveInfinity`). The decoder immediately extracts the nearest pre-existing I-frame/keyframe, yielding instantaneous thumbnail generation.

---

## 4. Phase 3: UX Streamlining (The Removal of Legacy UI Clutter)

With the native extension pipeline handling 100% of video playback, the old UI paradigms became obsolete:

- **Menu Bar Icon Removal**: Manual `Pause`, `Mute`, and `Stop` buttons were relics of the floating window hack. In the native pipeline, macOS automatically pauses rendering when apps are fullscreen, when displays sleep, or when Low Power Mode is enabled. Removing the status item gives users a clutter-free menu bar.
- **LaunchAgent Removal**: Because macOS's `WallpaperAgent` autonomously restores and loops the active wallpaper across reboots, LumaWall no longer requires a background daemon (`com.lumawall.app.plist`) running at login.

---

## 5. Architectural Comparison Summary

| Feature | Legacy Floating Window Hack | LumaWall Native ExtensionKit |
| :--- | :---: | :---: |
| **Lock Screen Live Motion** | ❌ No (Freezes / Black Screen) | ✅ **Yes (Hardware accelerated)** |
| **Lock Screen to Desktop Transition** | ❌ Desynchronized / Glitchy | ✅ **100% Seamless** |
| **Mission Control & Spaces** | ⚠️ Lag & visual stutter | ✅ **Integrated into Compositor** |
| **macOS System Settings Integration**| ❌ None | ✅ **Appears directly in Wallpaper pane** |
| **Disk Storage Overhead** | ⚠️ Duplicates file size | ✅ **0 MB extra (APFS clone)** |
| **Background Daemon Required** | ⚠️ Yes (Keeps window alive) | ✅ **No (Native WallpaperAgent)** |
| **System Security** | ⚠️ Unsanitized window level | ✅ **Strict App Sandbox compliance** |
