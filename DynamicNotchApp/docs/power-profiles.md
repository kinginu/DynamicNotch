# Power Profiles (F2)

Rules that switch the **fan profile** and **Low Power Mode** by context: power source, lid
(clamshell) and time of day. Settings ▸ **Power Profiles**; a one-line status appears under the
Fan Control widget's header while they are on.

Off by default with no rules: nothing changes until the user turns **Use Power Profiles** on.

## Rules

Each rule has conditions (all must hold) and actions:

| | Choices |
|---|---|
| Power Source | Any · Power Adapter · Battery |
| Lid | Any · Open · Closed (Clamshell). "Open" also matches a Mac without a lid (= not in clamshell mode). |
| Time | Optional window `From`–`To` (local time, half-open, minute resolution). `22:00–07:00` wraps past midnight; equal start and end = all day. Optional weekdays; the part after midnight belongs to the day the window started. |
| Fan Profile | Don't Change · one of the seven fixed profiles |
| Low Power Mode | Don't Change · On · Off |

**First match wins:** rules are checked from top to bottom (reorder with the arrows); disabled
rules are skipped. A rule after an enabled rule without conditions is marked "Never used".
Templates: *On Battery* (Automatic + Low Power Mode on), *Clamshell on Power Adapter* (Boost + Low
Power Mode off), *Quiet Nights* (22:00–07:00, Constant Quiet).

The rules are stored as JSON in UserDefaults (`fanControl.powerProfiles`).

## When things switch

The engine (`PowerProfileEngine`, FanControlKit) re-evaluates on power-source changes (IOKit
power-source notifications), lid changes (`AppleClamshellState` of `IOPMrootDomain`), wake, Low
Power Mode changes and a 30-second tick (time windows). It acts on **transitions** only: while the
matching rule stays the same nothing is written again, so a manual change is not fought every tick.

### Precedence

`manual > emergency > workload > power > default`

- **manual**: a fan profile you choose yourself (widget, menu, settings). It stays until the
  situation changes — the rules would pick a different profile — or until you click **Resume**
  (status line) / **Resume Rules** (settings). Your pick also becomes your default.
- **emergency**: reserved for automatic claims that must beat the others.
- **workload**: per-app / workload profiles (F3).
- **power**: these rules.
- **default**: the profile you had before the rules took over (or your last manual pick); the fans
  return to it when no rule matches, or when Power Profiles are turned off.

The 95 °C **all-fans-maximum safety override** is not part of this list: it works below the profile
layer and always applies, whatever profile is active.

Fan profiles are switched through `FanControlManager.applyProfile` (like the widget) and only
while **Fan Control** is enabled (Settings ▸ Fan Control ▸ General). A failed switch (e.g. the
helper is not installed) is shown in the status line / settings and not retried until the
situation changes.

### Low Power Mode

Changing Low Power Mode needs root, so it goes through the fan control helper's dedicated request
(`setLowPowerMode(battery:ac:)`, selector `setLowPowerModeWithBattery:ac:reply:`, still protocol 2:
`/usr/bin/pmset -a|-b|-c lowpowermode 0|1` and `pmset -g custom` with a fixed argv, allowlisted,
rate-limited, read back; FanControl/docs/helper.md "Low Power Mode request"). The request goes over
its own short-lived connection, not the fan session's, so a slow pmset never holds up fan writes.
The app never installs or registers the helper for this; without it the rule's Low Power Mode
action fails with an error and the fan part still works.

- Before the first change the current value is remembered **per power source** (battery and AC,
  read with `pmset -g custom`); when no rule asks for a value any more (no match, "Don't Change",
  Power Profiles off) both values are written back — equal values with one `pmset -a`, different
  ones with `-b` / `-c`, so "Only on Battery" / "Only on Power Adapter" comes back exactly.
- The memory is cleared only after a successful restore. A failed change or restore is retried at
  most every 60 s, and the first evaluation after launch always syncs, so a value remembered
  before a quit or crash is restored even when no rule matches.
- If you change Low Power Mode yourself meanwhile (Control Center, System Settings), your value is
  kept: nothing is written back.
- The memory survives a relaunch (`fanControl.powerProfiles.lowPowerModeMemory`; memories written
  before the per-source change still decode).
- A rule's **On** / **Off** sets both sources (`pmset -a`, like "Always" / "Never" in System
  Settings ▸ Battery); only the restore writes per source.
- Read-back: `ProcessInfo.processInfo.isLowPowerModeEnabled` (live), `pmset -g` (settings ▸ Now
  ▸ Check pmset) and `pmset -g custom` (per source; the helper reads it before and after a change).

## Focus

Not supported. There is no public API that tells which Focus is active: `INFocusStatusCenter`
only reports whether *some* Focus is on (`isFocused`), needs authorization, and requires the
Communication Notifications capability (an entitlement that needs a provisioning profile, which this
ad-hoc signed build does not have). Reading Focus state from private files or
`defaults` is fragile and was left out deliberately.

## Trying it safely

1. Build and run the app; re-run `sudo FanControl/Support/manual-install/install.sh <app>` after the
   rebuild (the helper now speaks protocol 2; an older helper refuses Low Power Mode with
   "re-run install.sh" and fan sessions with a version mismatch).
2. Settings ▸ Power Profiles: add the *On Battery* template, but first set its Low Power Mode to
   **Don't Change** and its fan profile to **Automatic** — this tries switching without touching
   Low Power Mode or forcing fans. Turn on **Use Power Profiles**.
3. Unplug the power adapter: the status line shows "On Battery · Automatic"; plug it back in: the
   previous profile returns.
4. Then try Low Power Mode **On** for that rule. Watch `pmset -g custom | grep -E 'Power:|lowpowermode'` and the helper
   log (`/usr/bin/log stream --predicate 'subsystem == "com.example.dynamicnotch.DynamicNotch" AND category == "fancontrol-helper"'`).
   Plugging back in should restore your original value.
5. To undo everything: turn **Use Power Profiles** off (fans return to your profile, Low Power Mode
   to your value). Manually: `sudo pmset -a lowpowermode 0`.

## Code

| File | Contents |
|---|---|
| `FanControl/Sources/FanControlCore/PowerProfileRules.swift` | Rule model, time windows, first match |
| `FanControl/Sources/FanControlCore/ProfileArbitration.swift` | Precedence layers and manual override |
| `FanControl/Sources/FanControlKit/PowerProfileEngine.swift` | Engine, Low Power Mode bookkeeping, status |
| `FanControl/Sources/FanControlKit/FanProfileArbiter.swift` | Applies the precedence decision |
| `FanControl/Sources/FanControlKit/PowerContextMonitor.swift` | Power source / lid / tick context |
| `FanControl/Sources/FanControlKit/LowPowerModeControl.swift` | `setLowPowerMode` client, readers |
| `FanControl/Sources/FanControlXPC/LowPowerModeCommand.swift` | Fixed argv, allowlist, parser, handler |
| `FanControl/Sources/FanControlHelper/LowPowerModeService.swift` | Helper XPC entry point |
| `FanControl/Sources/FanControlUI/PowerProfiles/FanControlPowerProfilesSettingsView.swift` | Settings pane (`FanControlPowerProfilesSettingsView`), start-up hook (`FanControlPowerProfiles.start()`) |
| `FanControl/Sources/FanControlUI/PowerProfiles/FanControlPowerProfileStatusLine.swift` | Widget status line |
| `DynamicNotchApp/Sources/FanControlGlue/FanControlWidgetView.swift`, `DynamicNotchApp/Sources/SettingsRootView.swift`, `DynamicNotchApp/Sources/Support/FanControl-Patches.swift` | Host hunks (`// F2:`, fan-control-integration.md (h)) |
