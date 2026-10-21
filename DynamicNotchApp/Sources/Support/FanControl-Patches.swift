// The hooks (d) and (e) of docs/fan-control-integration.md, and the glue between the app
// module and the FanControlUI library.
// Compiled only when the FanControl package is linked (the Xcode target); the CLT harness
// (Package.swift) does not depend on FanControl, so `canImport(FanControlKit)` is false there.
#if canImport(FanControlKit)
import AppKit
import SwiftUI
import FanControlCore
import FanControlKit
import FanControlUI



// SettingsRootView, NookWidget, NotchView, DebugHooks and the widget gallery name these types
// without `import FanControlUI` (they predate the library, when the types were drop-ins in this
// module). Module-level aliases keep them compiling; files that import FanControlUI see the
// same types.
typealias FanControlSettingsView = FanControlUI.FanControlSettingsView
typealias FanControlProfilesTabView = FanControlUI.FanControlProfilesTabView
typealias FanControlProfiles = FanControlUI.FanControlProfiles
typealias FanControlWidgetSettings = FanControlUI.FanControlWidgetSettings
typealias FanControlTemperatureWidgetSettings = FanControlUI.FanControlTemperatureWidgetSettings
typealias FanControlPowerProfilesSettingsView = FanControlUI.FanControlPowerProfilesSettingsView  // F2

// MARK: Host-store keys for the Fan Control settings the app reads itself

// NookWidget (grid size, `prefs`) and NotchView (row width) read these through the app's own
// `SettingsStore` (SettingsStorage.swift). Same UserDefaults keys as FanControlUI's
// `FanControlSettingKey.widget` / `.temperatureWidget`, so both stores see every write. The
// values conform to the app's `CodableStoredValue` through `Preferences` (NookWidget.swift).
extension StoredKeys {
    static let fanControlWidgetSettings = Key<FanControlWidgetSettings>(
        FanControlSettingKey.widget.name, default: .init())
    static let fanControlTemperatureWidgetSettings = Key<FanControlTemperatureWidgetSettings>(
        FanControlSettingKey.temperatureWidget.name, default: .init())
}

// MARK: (d) settings tab

// The host's settings window is SwiftUI's native `Settings` scene (Sources/SettingsRootView.swift):
// a `TabView` whose tags are `AppSettings.PaneIdentifier`s. The Fan Control tab is added there,
// before About:
//     tab(AppSettings.PaneIdentifier("fanControl"), "Fan Control", "fan") { FanControlSettingsView() }
// This identifier lets AppKit code open it: `WindowsManager.shared.showSettings(pane: .fanControl)`.
extension AppSettings.PaneIdentifier {
    static let fanControl = Self("fanControl")
    // F2: Power Profiles tab (fan-control-integration.md (h)).
    static let powerProfiles = Self("powerProfiles")
}

// MARK: (e) applicationDidFinishLaunching

enum FanControlStartup {
    /// Called from AppDelegate.applicationDidFinishLaunching (fan-control-integration.md (e)). Creates the alert
    /// coordinator (which syncs pollingInterval / reapplyProfileAfterWake / keepAlertsWhilePaused
    /// into FanControlManager) and starts read-only monitoring only if the user enabled the feature
    /// and auto-start. Never registers or contacts the helper by itself.
    @MainActor static func applicationDidFinishLaunching() {
        FanControlAlertCoordinator.shared.onAlertChange = { alert in
            if alert != nil {
                ActiveLiveActivitiesManager.shared.insertSync(.fanAlert)
            } else {
                ActiveLiveActivitiesManager.shared.removeSync(.fanAlert)
            }
        }
        // Team ID: not set (ad-hoc / manual-install personal mode, FanControl/docs/helper.md §6).
        // "Install Helper…" / "Uninstall Helper…" run the bundled manual-install scripts.
        FanControlHelperInstallerAction.register()
        let fanSettings = FanControlSettingKey.general.value
        if fanSettings.isEnabled && fanSettings.autoStartMonitoring {
            FanControlManager.shared.startMonitoring()
        }
        // F2: Power Profiles (fan-control-integration.md (h)); inert while the user has not turned them on.
        FanControlPowerProfiles.start()
        // F3: workload-linked profiles (fan-control-integration.md (i)); claims the arbiter's .workload layer.
        WorkloadProfileCoordinator.shared.start()
    }
}
#endif
