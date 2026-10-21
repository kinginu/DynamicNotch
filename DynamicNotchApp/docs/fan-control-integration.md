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
| `FanControlHelperInstallerAction.swift` | Sets `FanControlHostActions.installHelper` / `.uninstallHelper` to run the bundled `install.sh` / `uninstall.sh` as root (§6 "Helper installer") |

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
  `FanControlManager`), forwards alerts to the live activities, registers the "Install Helper…" /
  "Uninstall Helper…" actions (§6), and starts read-only monitoring only when the user has enabled
  the feature (off by default).
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
FanControl's manual-install mode: `install.sh` copies the helper to `/Library/PrivilegedHelperTools/`,
writes a root-owned LaunchDaemon plist whose client requirement pins the app's bundle id and
cdhash, and bootstraps it. The app in turn checks the installed helper's cdhash before connecting.
Every build (and so every update) changes the app's cdhash, so the helper has to be installed again
after each one; until then Settings ▸ Fan Control ▸ General says the helper is pinned to another
build. `uninstall.sh` and `status.sh` sit next to it (`FanControl/Support/manual-install/README.md`,
`FanControl/docs/helper.md` §6).

### Helper installer (bundled scripts and the "Install Helper…" button)

- **Bundled scripts.** `project.yml` copies `FanControl/Support/manual-install/*` and the two
  libraries they source (`lib.sh`, `identifiers.sh`) flat into
  `DynamicNotch.app/Contents/Resources/manual-install/` (the executable bits are kept). `common.sh`
  finds the libraries next to itself in that layout and one level up in the source tree. From
  Terminal:

  ```sh
  M=/Applications/DynamicNotch.app/Contents/Resources/manual-install
  $M/install.sh --dry-run /Applications/DynamicNotch.app    # preview, no root
  sudo $M/install.sh /Applications/DynamicNotch.app         # install / update
  $M/status.sh /Applications/DynamicNotch.app               # read-only check
  sudo $M/uninstall.sh /Applications/DynamicNotch.app       # remove
  ```

- **The buttons.** FanControlUI exposes the host hook `FanControlHostActions.installHelper` /
  `.uninstallHelper` (`FanControl/docs/helper.md` §6 "Installing from the app").
  `FanControlStartup` (hook (e)) calls `FanControlHelperInstallerAction.register()`
  (`Sources/FanControlGlue/FanControlHelperInstallerAction.swift`), which sets both when the
  bundled scripts exist. Settings ▸ Fan Control ▸ General ▸ Helper then shows **Install Helper…**
  while the helper is not installed, is pinned to another build, or is refused, and **Uninstall
  Helper…** while it is installed manually. A successful install is followed by "Check Again"
  (`retryHelperConnection()`); the installer's output appears under "Installer Output" while it
  runs and stays there afterwards (expanded after a failure).
- **How it runs** (`Sources/Support/AdministratorScript.swift`, `HelperInstallerCommands.swift`):
  `/usr/bin/osascript` with a constant AppleScript, `do shell script (item 1 of argv) with prompt
  (item 2 of argv) with administrator privileges`, so macOS shows its administrator password
  dialog ("DynamicNotch wants to install its fan control helper."). The shell command is the
  osascript argument, never part of the AppleScript text, and every word of it is single-quoted:
  `'/bin/bash' '<app>/Contents/Resources/manual-install/install.sh' '--app' '<app>'`, stdin from
  `/dev/null`, output appended to a log file the app created in a fresh 0700 temporary directory
  (read every 0.25 s for the live output), then the exit status as a marker line. Cancelling the
  dialog (AppleScript error -128) changes nothing and shows nothing; a non-zero exit shows the
  script's last `error:` line in the pane's footer.
- **Trust.** The scripts run as root from the app bundle, which the user owns. That is the same
  trust as typing `sudo …/install.sh` in Terminal: whoever can modify the bundle could already
  change what the user runs. The password dialog is macOS's own; the app never sees the password.
- **Tests.** `Tests/DynamicNotchAppTests/AdministratorScriptTests.swift` (CLT harness and Xcode):
  quoting round trips through `/bin/sh` for hostile paths (quotes, `$(…)`, backticks, newlines),
  argument passing and the exit-status marker, the constant AppleScript, the outcome mapping
  (success, failure, cancel, osascript errors), and an end-to-end run of the real `install.sh
  --help` / `--dry-run` through osascript **without** administrator privileges. The privileged path
  itself (the password dialog and a real install) is only tested by hand.
