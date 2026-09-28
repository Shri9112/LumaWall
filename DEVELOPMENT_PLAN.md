# LumaWall Development Plan

## 1. Project Goals

**LumaWall** is a native macOS application engineered for Apple Silicon (specifically M2 and newer Macs) that turns any local video file (MP4, MOV, H.264, HEVC) into an animated live desktop wallpaper.

### Key Objectives
1. **Seamless Desktop Integration**: Render behind Finder desktop icons and regular windows without disrupting interaction or stealing focus.
2. **Zero-Glitch Looping**: Ensure continuous playback using AVFoundation hardware looping without black frames or frame drops.
3. **M2 Hardware Efficiency**: Leverage Apple Silicon Media Engine decoders; zero frame copying to CPU.
4. **Energy Management**: Strictly event-driven; auto-pause on sleep, screen lock, display power-off, and optional battery-saving mode.
5. **Multi-Monitor Flexibility**: Support independent or mirrored wallpaper playback per physical display.
6. **Robust File Handling**: Never duplicate user videos; reference local files with security-scoped bookmarks and lightweight metadata caching.
7. **Clean Native Experience**: Native AppKit + SwiftUI interface and menu-bar companion; offline-first, private, and SIP-safe.

---

## 2. Technology Choices

| Domain | Technology | Justification |
| :--- | :--- | :--- |
| **Language** | Swift 6 | Memory-safe, concurrency-safe, Apple native standard |
| **Windowing & Desktop Integration** | AppKit (`NSWindow`, `NSScreen`) | Direct access to window levels, borderless masks, mouse event passthrough, and spaces collection behaviors |
| **User Interface** | SwiftUI | Modern, responsive, clean macOS design for Library, Settings, and Inspector |
| **Video Playback** | AVFoundation (`AVQueuePlayer`, `AVPlayerLooper`, `AVPlayerLayer`) | Zero-overhead hardware acceleration via M2 Media Engine; CoreMedia seamless looping |
| **Thumbnail Generation** | `AVAssetImageGenerator` | Efficient single-frame extraction without decoding entire video streams |
| **System Event Management** | `NSWorkspace`, `IOPowerSources`, `DistributedNotificationCenter` | Event-driven sleep/wake, lock/unlock, battery state tracking without CPU polling |
| **Login Item** | `ServiceManagement` (`SMAppService`) | Modern Apple standard for launch at login |
| **Logging** | Unified Logging (`os.Logger`) | Low-overhead subsystem-categorized logging |
| **Build System** | Swift Package Manager (SPM) | Standard, portable, zero-dependency native macOS build system |

---

## 3. Milestones & Phases

```
┌─────────────────────────────────────────────────────────────┐
│ PHASE 0: Environment & Architecture Validation (Current)    │
│ • Detect toolchain, verify APIs, establish project skeleton  │
│ • Write ARCHITECTURE.md and DEVELOPMENT_PLAN.md             │
│ • Minimal build and launch verification                     │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│ PHASE 1: AVFoundation Playback & Looping Engine             │
│ • VideoValidator (MP4/MOV, H.264/HEVC format detection)     │
│ • AVPlayerLooper integration & seamless looping engine      │
│ • Video metadata extraction & thumbnail generator           │
│ • Unit tests for metadata and validator                     │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│ PHASE 2: Desktop Wallpaper Window Layer                     │
│ • WallpaperWindow (desktopWindow level, pass-through mouse) │
│ • Multi-space collection behavior (.canJoinAllSpaces)       │
│ • Verification on active display behind desktop icons       │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│ PHASE 3: Wallpaper Library & SwiftUI UI                     │
│ • Local persistence store (JSON-based metadata cache)       │
│ • SwiftUI Library Grid, File Picker, Preview Player         │
│ • Add, remove, select wallpaper, status feedback            │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│ PHASE 4: Multi-Monitor Support                              │
│ • DisplayManager tracking screen additions/removals         │
│ • Independent vs. unified display wallpaper assignment      │
│ • Clamshell mode and resolution change handling             │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│ PHASE 5: Energy & Power Management                          │
│ • Sleep/wake, display sleep, and screen lock observers      │
│ • Battery power source detection (pause on battery)         │
│ • App backgrounding optimizations                           │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│ PHASE 6: Menu Bar Companion & Launch at Login               │
│ • NSStatusItem menu with quick play/pause/switch actions    │
│ • SMAppService integration for Launch at Login              │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│ PHASE 7: QA, Performance Validation & Documentation         │
│ • PERFORMANCE.md profiling results (CPU, GPU, RAM)          │
│ • TESTING.md complete test checklist & manual test procedures│
│ • Comprehensive README.md and packaging script              │
└─────────────────────────────────────────────────────────────┘
```

---

## 4. Key Risks and Mitigation Strategies

| Risk | Impact | Mitigation Strategy |
| :--- | :--- | :--- |
| **Spaces Glitches / Window Hiding** | Wallpaper disappears when switching desktops | Set `.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]`. |
| **Desktop Icon Overlap** | Wallpaper obscures desktop files or blocks clicking | Ensure `window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))` and `window.ignoresMouseEvents = true`. Desktop icons reside 20 levels higher at `kCGDesktopIconWindowLevelKey`. |
| **High Battery Drain from 4K Video** | High energy consumption on MacBook | Hardware-accelerated decoding via `AVPlayerLayer`; event-driven pause during sleep/lock/battery; zero timer loops. |
| **Looping Stutter or Black Frame** | Jarring pause at end of video | Use `AVPlayerLooper` with `AVQueuePlayer` to pre-buffer the upcoming loop cycle in CoreMedia. |
| **Moved or Deleted Video Files** | App crashes or hangs | `VideoValidator` checks file existence, read accessibility, and tracks files via security-scoped bookmarks; displays clean UI error states instead of crashing. |
| **Multi-Display Dynamic Reconfiguration** | Windows left in orphaned frames on unplug | `DisplayManager` subscribes to `NSApplication.didChangeScreenParametersNotification` and reallocates window controllers to active screens. |

---

## 5. Testing Strategy

1. **Automated Unit Testing (`swift test`)**:
   - `VideoValidatorTests`: Test validation of valid vs invalid files, missing files, corrupted headers.
   - `VideoMetadataTests`: Verify parsing of video dimensions, duration, format names, and aspect ratios.
   - `LibraryStoreTests`: Test serialization, persistence, insertion, deletion, and reload of wallpaper metadata.
   - `DisplayConfigurationTests`: Verify display assignment mapping logic (unified vs independent mode).
2. **Manual & Visual QA Procedures (`TESTING.md`)**:
   - Desktop icon click-through and drag marquee verification.
   - Spaces switching and Mission Control animation smoothness.
   - External display connect/disconnect stress test.
   - Laptop lid close (clamshell mode) and sleep/wake transition.
   - CPU and memory profiling using `Activity Monitor` and `powermetrics`.

---

## 6. Future Roadmap (Post-v1)

- Live audio-reactive visualizers (Metal-based).
- Customizable clock, weather, and calendar desktop overlays.
- Dynamic time-of-day wallpaper switching (day/night transitions).
- Playlist mode with timed rotation (e.g. switch wallpaper every hour).
- Folder auto-sync daemon observing `~/Movies/Live Wallpapers/`.
