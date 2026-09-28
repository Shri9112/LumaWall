import AppKit
import Foundation
import IOKit.ps
import Observation

/// Coordinates event-driven power management, sleep/wake, screen lock, and battery awareness.
@Observable
@MainActor
public final class PowerManager {
    public static let shared = PowerManager()

    public var settings: AppSettings {
        didSet {
            evaluateSuspension()
        }
    }

    public private(set) var isOnBattery: Bool = false
    public private(set) var isDisplaySleeping: Bool = false
    public private(set) var isSystemSleeping: Bool = false
    public private(set) var isScreenLocked: Bool = false
    public private(set) var isSuspended: Bool = false

    private var wasPlayingBeforeSuspension: Bool = false
    private var powerRunLoopSource: CFRunLoopSource?
    private var workspaceObservers: [any NSObjectProtocol] = []
    private var distributedObservers: [any NSObjectProtocol] = []

    public init(settings: AppSettings = AppSettings()) {
        self.settings = settings
        self.isOnBattery = Self.checkIsRunningOnBattery()

        setupPowerSourceObserver()
        setupWorkspaceObservers()
        setupDistributedObservers()
    }

    // MARK: - Power Source Detection (Zero Polling)

    public static func checkIsRunningOnBattery() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return false }
        guard let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else { return false }

        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            if let state = desc[kIOPSPowerSourceStateKey] as? String {
                return state == kIOPSBatteryPowerValue
            }
        }
        return false
    }

    private func setupPowerSourceObserver() {
        let callback: IOPowerSourceCallbackType = { _ in
            Task { @MainActor in
                PowerManager.shared.handlePowerSourceChanged()
            }
        }

        if let source = IOPSNotificationCreateRunLoopSource(callback, nil)?.takeRetainedValue() {
            self.powerRunLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    private func handlePowerSourceChanged() {
        let newIsOnBattery = Self.checkIsRunningOnBattery()
        if newIsOnBattery != self.isOnBattery {
            self.isOnBattery = newIsOnBattery
            LumaLogger.power.info("Power source changed: onBattery = \(newIsOnBattery)")
            evaluateSuspension()
        }
    }

    // MARK: - Workspace & System Sleep Observers

    private func setupWorkspaceObservers() {
        let nc = NSWorkspace.shared.notificationCenter

        // 1. System Sleep
        let sleepObs = nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                LumaLogger.power.info("System will sleep: pausing wallpapers")
                self?.isSystemSleeping = true
                self?.evaluateSuspension()
            }
        }
        workspaceObservers.append(sleepObs)

        // 2. System Wake
        let wakeObs = nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                LumaLogger.power.info("System did wake: restoring wallpapers")
                self?.isSystemSleeping = false
                self?.evaluateSuspension()
            }
        }
        workspaceObservers.append(wakeObs)

        // 3. Screens Did Sleep
        let screenSleepObs = nc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                LumaLogger.power.info("Screens did sleep: halting GPU rendering")
                self?.isDisplaySleeping = true
                self?.evaluateSuspension()
            }
        }
        workspaceObservers.append(screenSleepObs)

        // 4. Screens Did Wake
        let screenWakeObs = nc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                LumaLogger.power.info("Screens did wake: restoring rendering")
                self?.isDisplaySleeping = false
                self?.evaluateSuspension()
            }
        }
        workspaceObservers.append(screenWakeObs)
    }

    // MARK: - Screen Lock Observers

    private func setupDistributedObservers() {
        let dc = DistributedNotificationCenter.default()

        // 1. Screen Locked
        let lockObs = dc.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                LumaLogger.power.info("Screen is locked: pausing wallpapers")
                self?.isScreenLocked = true
                self?.evaluateSuspension()
            }
        }
        distributedObservers.append(lockObs)

        // 2. Screen Unlocked
        let unlockObs = dc.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                LumaLogger.power.info("Screen is unlocked: evaluating playback")
                self?.isScreenLocked = false
                self?.evaluateSuspension()
            }
        }
        distributedObservers.append(unlockObs)
    }

    // MARK: - State Evaluation

    public func evaluateSuspension() {
        let shouldSuspend = isSystemSleeping ||
            (settings.pauseOnDisplaySleep && isDisplaySleeping) ||
            (settings.pauseOnScreenLock && isScreenLocked) ||
            (settings.pauseOnBattery && isOnBattery)

        if shouldSuspend && !isSuspended {
            // Entering suspension
            isSuspended = true
            wasPlayingBeforeSuspension = DisplayManager.shared.isPlaying
            DisplayManager.shared.pauseAll()
            LumaLogger.power.info("Suspended playback (battery=\(self.isOnBattery), displaySleep=\(self.isDisplaySleeping), locked=\(self.isScreenLocked))")
        } else if !shouldSuspend && isSuspended {
            // Exiting suspension
            isSuspended = false
            if wasPlayingBeforeSuspension {
                DisplayManager.shared.resumeAll()
                LumaLogger.power.info("Resumed playback after clearing suspension conditions")
            }
        }
    }

    // MARK: - Manual Testing Hooks

    public func simulateBatteryState(_ onBattery: Bool) {
        self.isOnBattery = onBattery
        evaluateSuspension()
    }

    public func simulateDisplaySleep(_ sleeping: Bool) {
        self.isDisplaySleeping = sleeping
        evaluateSuspension()
    }

    public func simulateScreenLock(_ locked: Bool) {
        self.isScreenLocked = locked
        evaluateSuspension()
    }
}
