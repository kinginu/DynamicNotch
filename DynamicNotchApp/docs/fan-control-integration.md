# How DynamicNotch hosts FanControl

DynamicNotch gets its fan control from the [FanControl](https://github.com/kinginu/FanControl)
package, checked out as the git submodule `FanControl/` at the repository root. The package does
everything that is not specific to this app: SMC reads, the control loop, profiles, the safety
policy, the privileged helper, and a host-independent SwiftUI layer (`FanControlUI`). This app
adds four things on top: the glue files, a handful of hook points in its own sources, the helper
target, and the manual helper install. The package's own documentation is the reference for the
API: `FanControl/docs/integration.md` (targets, signing, wiring), `FanControl/docs/kit.md` (app
side) and `FanControl/docs/helper.md` (helper).

## 1. Package products

`project.yml` adds `../FanControl` as a local package and links `FanControlCore`, `FanControlKit`
and `FanControlUI` into the app target, the test-support library and the test bundle.
`FanControlUI` provides the settings pane (`FanControlSettingsView` with its General / Profiles /
Sensors / Automation tabs), the curve view and editor, the temperature chart, the alert
coordinator, the Power Profiles pane and the stored settings (`@FanControlSetting`,
`FanControlSettingKey`).

The Command Line Tools harness (`Package.swift`) does not depend on FanControl. Every use of it
in `Sources/` is wrapped in `#if canImport(FanControlKit)`, and `Sources/FanControlGlue/` is
excluded from the harness target.

## 2. Glue files (`Sources/FanControlGlue/`)

| File | What it is |
|---|---|
| `FanControlWidgetView.swift` | The Fan Control Nook widget: fans, the profile list, the selected profile's curve |
| `FanControlWidgetSettingsView.swift` | Its options in Settings ▸ Widgets |
| `FanControlTemperatureWidgetView.swift` | The Temperature Nook widget (CPU / GPU / SSD history, `FanControlTemperatureChart`) |
| `FanControlTemperatureWidgetSettingsView.swift` | Its options in Settings ▸ Widgets |
| `FanControlLiveActivity.swift` | `FanControlAlertView`, the closed-notch fan alert |
| `FanControlNookHooks.swift` | `FanControlNookVisibility` (pause polling while the Nook is hidden) and `FanControlWidgetPresence` |

`Sources/Support/FanControl-Patches.swift` holds the module-level type aliases for files that do
not import `FanControlUI`, the host-store keys for the two widget settings (same `UserDefaults`
keys as `FanControlSettingKey`, so both stores see every write), the settings pane identifiers and
`FanControlStartup`.

## 3. Hook points in the app

Each hook is marked in the code with a comment naming its letter, e.g.
`// fan-control-integration.md (a)`.

- **(a) `NookWidget.swift`**: the widget cases `fanControl` (tag 8) and `temperature` (tag 11),
  appended so stored values stay valid, with their icon, name, grid size (`2x1` = 100 pt or
  double-wide = 250 pt; Temperature is always 250 pt) and `prefs`. `FanControlWidgetSettings` and
  `FanControlTemperatureWidgetSettings` conform to `Preferences` / `WidgetPrefs`.
- **(b) `Support/NookWidgetGrid.swift`**: the widget → view switch returns
  `FanControlWidgetView()` / `FanControlTemperatureWidgetView()`, and the grid widths.
  **(b-2) `NotchView.swift`**: calls `FanControlNookVisibility.nookVisibilityChanged(isVisible:)`
  when the Nook opens or closes, which pauses polling while it is hidden (if the user enabled
  that). The widgets' own appear / disappear is only a fallback.
- **(c) `WidgetsSettingsTabView.swift`**: the per-widget settings views.
- **(d) `SettingsRootView.swift`**: a "Fan Control" tab (`FanControlSettingsView`, 760×640 like
  every pane) before About. `WindowsManager.shared.showSettings(pane: .fanControl)` opens it.
- **(e) `AppDelegate.applicationDidFinishLaunching`** → `FanControlStartup`: creates
  `FanControlAlertCoordinator.shared` (it mirrors the stored settings and thresholds into
  `FanControlManager`), forwards alerts to the live activities, and starts read-only monitoring
  only when the user has enabled the feature (off by default).
- **(f) `LiveActivities/`**: the `fanAlert` live activity (`gate: .always`, priority 100), drawn
  by `FanControlAlertView(part:)` on both sides of the notch.
- **(g) Termination and wake**: nothing to add. `FanControlManager` hands the fans back to macOS on
  `willTerminate` and re-applies the profile after wake by itself.
- **(h) Power Profiles**: a "Power Profiles" settings tab (`FanControlPowerProfilesSettingsView`),
  `FanControlPowerProfiles.start()` at launch and `FanControlPowerProfileStatusLine` in the widget
  (see `docs/power-profiles.md`).
- **(i) Workload automation**: `Sources/Support/WorkloadProfileCoordinator.swift` drives
  FanControlKit's `WorkloadProfileEngine` from `NSWorkspace` notifications and a CPU / GPU load
  sampler; it is started after (h). The widget header shows `FanControlAutomationIndicator()`.

## 4. Strings

`FanControlUI` and the glue look their labels up in the app's `Localizable.strings` (keys are the
English text). They live in `Support/strings/fan-control.json` (and
`fan-control-automation.json`, `power-profiles.json`); `Support/merge-strings.py` generates
`Localization/en.lproj/Localizable.strings` and `Support/lint-strings.py` checks the sources,
including `FanControl/Sources/FanControlUI`, against it.

## 5. Helper target

`FanControlHelper` is an Xcode Command Line Tool target built from
`../FanControl/Sources/FanControlHelper`, with `FanControl/Support/Helper-Info.plist` embedded by
`-sectcreate __TEXT __info_plist` (`FanControl/docs/integration.md` §2). The app embeds it in
`Contents/MacOS/` and copies the launchd plist into `Contents/Library/LaunchDaemons/` for the
`SMAppService` path (§3). Both are ad-hoc signed with the Hardened Runtime.

## 6. Manual helper install

Without a Developer ID Team ID, `SMAppService` cannot register the helper, so this app uses
FanControl's manual-install mode: `sudo FanControl/Support/manual-install/install.sh --app <path to
DynamicNotch.app>` copies the helper to `/Library/PrivilegedHelperTools/`, writes a root-owned
LaunchDaemon plist whose client requirement pins the app's bundle id and cdhash, and bootstraps it.
The app in turn checks the installed helper's cdhash before connecting. Every rebuild changes the
app's cdhash, so `install.sh` has to be run again after each build; until then Settings ▸ Fan
Control ▸ General says the helper is pinned to another build. `uninstall.sh` and `status.sh` sit
next to it (`FanControl/Support/manual-install/README.md`, `FanControl/docs/helper.md` §6).
