// LoginItemManager — "Launch at login" through SMAppService.mainApp. The login item itself is the
// source of truth (the user can remove it in System Settings ▸ General ▸ Login Items), so
// `GeneralSettings.launchAtLogin` only mirrors `isEnabled`.
import Foundation
import ServiceManagement
import os

private let logger = Logger(subsystem: "com.example.dynamicnotch.DynamicNotch", category: "login-item")

enum LoginItemManager {
    /// Current registration state of the app's login item.
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    /// True when the app is registered (also while it waits for the user's approval).
    static var isEnabled: Bool {
        switch status {
        case .enabled, .requiresApproval: return true
        default: return false
        }
    }

    /// True when macOS needs the user to allow the item in System Settings ▸ Login Items.
    static var requiresApproval: Bool { status == .requiresApproval }

    /// Registers or unregisters the login item, then mirrors the resulting state into
    /// `GeneralSettings.launchAtLogin`. Returns the resulting state.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if status != .enabled { try SMAppService.mainApp.register() }
            } else if status != .notRegistered && status != .notFound {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("\(enabled ? "register" : "unregister", privacy: .public) failed: \(String(describing: error), privacy: .public)")
        }
        syncSetting()
        return isEnabled
    }

    /// Writes the real login-item state back into the stored setting (call on launch and when the
    /// settings pane appears).
    static func syncSetting() {
        let on = isEnabled
        if SettingsStore[.generalSettings].launchAtLogin != on {
            SettingsStore[.generalSettings].launchAtLogin = on
        }
    }

    /// Opens System Settings ▸ General ▸ Login Items (for the `.requiresApproval` case).
    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
