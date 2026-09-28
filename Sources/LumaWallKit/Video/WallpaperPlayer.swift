import Foundation
import AVFoundation
import AppKit
import Observation

public enum PlaybackState: Equatable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case failed(String)
}

@Observable
@MainActor
public final class WallpaperPlayer: NSObject {
    public private(set) var state: PlaybackState = .idle
    public private(set) var isMuted: Bool = true
    public private(set) var currentURL: URL?
    public private(set) var errorMessage: String?
    public private(set) var duration: TimeInterval = 0
    public private(set) var currentTime: TimeInterval = 0

    public var isPlaying: Bool {
        state == .playing
    }

    public let playerLayer: AVPlayerLayer

    private var queuePlayer: AVQueuePlayer
    private var looper: AVPlayerLooper?
    private var timeObserverToken: Any?
    private var statusObservation: NSKeyValueObservation?
    private var looperStatusObservation: NSKeyValueObservation?

    public init(isMuted: Bool = true) {
        self.isMuted = isMuted
        let player = AVQueuePlayer()
        self.queuePlayer = player
        self.playerLayer = AVPlayerLayer(player: player)

        super.init()

        // Configure player properties
        queuePlayer.isMuted = isMuted
        queuePlayer.volume = isMuted ? 0.0 : 1.0
        // CRITICAL: Live wallpapers must NOT prevent display sleep
        queuePlayer.preventsDisplaySleepDuringVideoPlayback = false
        queuePlayer.actionAtItemEnd = .none

        // Configure player layer
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]

        setupTimeObserver()
    }

    // MARK: - Public Controls

    /// Loads and begins looping the video at `url`.
    public func loadVideo(url: URL, autoPlay: Bool = true) {
        LumaLogger.video.info("Loading video into WallpaperPlayer: \(url.lastPathComponent)")

        // 1. Reset existing playback
        cleanupLooper()
        currentURL = url
        state = .loading
        errorMessage = nil

        // 2. Validate file existence
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            let msg = "Video file not found at path: \(url.path(percentEncoded: false))"
            LumaLogger.video.error("\(msg)")
            state = .failed(msg)
            errorMessage = msg
            return
        }

        // 3. Prepare AVPlayerItem and AVPlayerLooper
        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)

        // Observe player item status
        statusObservation = playerItem.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    let dur = CMTimeGetSeconds(item.duration)
                    self.duration = (dur.isFinite && dur > 0) ? dur : 0
                    if autoPlay {
                        self.play()
                    } else {
                        self.state = .paused
                    }
                    LumaLogger.video.info("PlayerItem readyToPlay (duration: \(self.duration)s)")
                case .failed:
                    let err = item.error?.localizedDescription ?? "Unknown playback error"
                    LumaLogger.video.error("PlayerItem failed: \(err)")
                    self.state = .failed(err)
                    self.errorMessage = err
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        }

        // Setup AVPlayerLooper for seamless hardware-level looping
        self.looper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)

        // Observe looper status
        if let looper = self.looper {
            looperStatusObservation = looper.observe(\.status, options: [.new]) { [weak self] looper, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if looper.status == .failed {
                        let err = looper.error?.localizedDescription ?? "Looping engine failed"
                        LumaLogger.video.error("AVPlayerLooper failed: \(err)")
                        self.state = .failed(err)
                        self.errorMessage = err
                    }
                }
            }
        }
    }

    /// Plays the current video
    public func play() {
        guard currentURL != nil else { return }
        queuePlayer.play()
        state = .playing
        LumaLogger.video.debug("WallpaperPlayer resumed playback")
    }

    /// Pauses the current video
    public func pause() {
        queuePlayer.pause()
        state = .paused
        LumaLogger.video.debug("WallpaperPlayer paused playback")
    }

    /// Toggles play / pause
    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    /// Updates audio mute state
    public func setMuted(_ muted: Bool) {
        self.isMuted = muted
        queuePlayer.isMuted = muted
        queuePlayer.volume = muted ? 0.0 : 1.0
        LumaLogger.video.debug("WallpaperPlayer audio muted: \(muted)")
    }

    /// Stops playback and clears items
    public func stop() {
        cleanupLooper()
        currentURL = nil
        duration = 0
        currentTime = 0
        state = .idle
        errorMessage = nil
        LumaLogger.video.info("WallpaperPlayer stopped")
    }

    // MARK: - Private Helpers

    private func cleanupLooper() {
        statusObservation?.invalidate()
        statusObservation = nil
        looperStatusObservation?.invalidate()
        looperStatusObservation = nil

        looper?.disableLooping()
        looper = nil

        queuePlayer.pause()
        queuePlayer.removeAllItems()
    }

    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserverToken = queuePlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let secs = CMTimeGetSeconds(time)
                if secs.isFinite && secs >= 0 {
                    self.currentTime = secs
                }
            }
        }
    }
}
