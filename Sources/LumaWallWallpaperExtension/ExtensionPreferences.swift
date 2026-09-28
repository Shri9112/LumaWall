import Foundation

public struct ActiveLockScreenConfig: Codable, Sendable {
    public var videoPath: String
    public var thumbnailPath: String
    public var isMuted: Bool

    public init(videoPath: String, thumbnailPath: String, isMuted: Bool = true) {
        self.videoPath = videoPath
        self.thumbnailPath = thumbnailPath
        self.isMuted = isMuted
    }
}

public final class ExtensionPreferences: @unchecked Sendable {
    public static let shared = ExtensionPreferences()

    private let lock = NSLock()
    private var currentConfig: ActiveLockScreenConfig?

    public static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/LumaWall", isDirectory: true)
            .appendingPathComponent("active_lockscreen.json")
    }

    private init() {
        reload()
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(
            center,
            Unmanaged.passUnretained(self).toOpaque(),
            { _, _, _, _, _ in ExtensionPreferences.shared.reload() },
            "com.lumawall.app.lockscreen-changed" as CFString,
            nil,
            .deliverImmediately
        )
    }

    public var config: ActiveLockScreenConfig? {
        lock.lock()
        defer { lock.unlock() }
        return currentConfig
    }

    public func reload() {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: Self.configURL),
              let decoded = try? JSONDecoder().decode(ActiveLockScreenConfig.self, from: data) else {
            return
        }
        self.currentConfig = decoded
    }
}
