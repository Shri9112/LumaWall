import Foundation
import ServiceManagement
import Observation

/// Coordinates macOS Launch at Login via Apple's official SMAppService API.
@Observable
@MainActor
public final class LoginItemManager {
    public static let shared = LoginItemManager()

    public private(set) var isEnabled: Bool = false
    public private(set) var statusDescription: String = "Not Registered"

    public init() {
        refreshStatus()
    }

    /// Queries the current registration state with SMAppService
    public func refreshStatus() {
        let status = SMAppService.mainApp.status
        switch status {
        case .enabled:
            self.isEnabled = true
            self.statusDescription = "Enabled (Launches at Login)"
        case .notRegistered:
            self.isEnabled = false
            self.statusDescription = "Not Registered"
        case .requiresApproval:
            self.isEnabled = false
            self.statusDescription = "Requires Approval in System Settings"
        case .notFound:
            self.isEnabled = false
            self.statusDescription = "Not Available (Packaged App Required)"
        @unknown default:
            self.isEnabled = false
            self.statusDescription = "Unknown Status"
        }
        LumaLogger.app.debug("SMAppService status: \(self.statusDescription)")
    }

    /// Enables or disables launch at login
    public func setLaunchAtLogin(enabled: Bool) throws {
        if enabled {
            try register()
        } else {
            try unregister()
        }
    }

    /// Registers the application as a login item
    public func register() throws {
        LumaLogger.app.info("Registering LumaWall as login item via SMAppService")
        do {
            try SMAppService.mainApp.register()
            refreshStatus()
        } catch {
            LumaLogger.app.error("Failed to register login item: \(error.localizedDescription)")
            refreshStatus()
            throw error
        }
    }

    /// Unregisters the application as a login item
    public func unregister() throws {
        LumaLogger.app.info("Unregistering LumaWall login item via SMAppService")
        do {
            try SMAppService.mainApp.unregister()
            refreshStatus()
        } catch {
            LumaLogger.app.error("Failed to unregister login item: \(error.localizedDescription)")
            refreshStatus()
            throw error
        }
    }
}
