import Foundation

public struct AppSettings: Codable, Sendable, Equatable {
    public var pauseOnBattery: Bool
    public var pauseOnDisplaySleep: Bool
    public var pauseOnScreenLock: Bool
    public var pauseOnFullscreen: Bool
    public var autoMuteAudio: Bool
    public var autoStartOnLaunch: Bool
    public var launchAtLogin: Bool

    public init(
        pauseOnBattery: Bool = false,
        pauseOnDisplaySleep: Bool = true,
        pauseOnScreenLock: Bool = true,
        pauseOnFullscreen: Bool = true,
        autoMuteAudio: Bool = true,
        autoStartOnLaunch: Bool = true,
        launchAtLogin: Bool = false
    ) {
        self.pauseOnBattery = pauseOnBattery
        self.pauseOnDisplaySleep = pauseOnDisplaySleep
        self.pauseOnScreenLock = pauseOnScreenLock
        self.pauseOnFullscreen = pauseOnFullscreen
        self.autoMuteAudio = autoMuteAudio
        self.autoStartOnLaunch = autoStartOnLaunch
        self.launchAtLogin = launchAtLogin
    }
}
