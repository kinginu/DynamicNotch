# Review of the 10 feature merges and the refactoring pass (2026-10-21)

> Line numbers are as of the review (2026-10-21); file names follow the current tree.

Scope: d280231..caf55c0 (feature merges F1–F10 + wiring) and 934f4dd..d280231 (refactor R1–R20). Method: 7 review slices (Opus), each finding adversarially verified by an independent agent. 44 confirmed (1 high, 20 medium, 23 low), 9 rejected.

Status: **all 44 fixed** (2026-10-21, on main after 7bfe01b): FanControl (group A) 81ac749, ec5e7a6, 9738cc0; Automation / HUD / AirPods (group B1) ed673d7, 42a7c8f, b0158f7; widget pages / Displays / Downloads / Calendar / Tray (group B2) 7b96e72, e4879d5, a7432d9, plus the TimerCreatorView scroll-monitor pass-through (B2's partial item) and the power-profiles.md update in the integration commit. The combined tree passes `scripts/check.sh` (12/12). The list below is kept as the record.

| # | Sev | File:line | Finding |
|---|---|---|---|
| 1 | high | `DynamicNotchApp/Sources/Automation/AutomationCommand.swift:316` | timer/start crashes the app when the duration overflows Int |
| 2 | medium | `DynamicNotchApp/Sources/AirPodsControlCenterDriver.swift:40` | Sound menu is left open when AXPress on the menu extra returns an error, because the `defer { close(...) }` is registered only after the press succeeds |
| 3 | medium | `DynamicNotchApp/Sources/AirPodsControlCenterDriver.swift:91` | close() checks the window count only once (after 0.15 s), so a menu that opens after openTimeout is never closed |
| 4 | medium | `DynamicNotchApp/Sources/Automation/CommandRouter.swift:99` | capture/screen lets any process get a full-screen screenshot under DynamicNotch's Screen Recording grant |
| 5 | medium | `DynamicNotchApp/Sources/Automation/LiveAutomationActions.swift:38` | Fan commands fail with 'No fans found' whenever monitoring has not polled yet |
| 6 | medium | `DynamicNotchApp/Sources/Automation/LiveAutomationActions.swift:39` | fan/auto never does anything once Automatic is the active profile |
| 7 | medium | `DynamicNotchApp/Sources/CalendarManager.swift:73` | CalendarManager's access status and today's events go stale when access is granted through PermissionCenter or System Settings |
| 8 | medium | `DynamicNotchApp/Sources/DownloadsWatcher.swift:665` | A Clear Old plan can appear after the user cancelled it and is never re-checked on confirm |
| 9 | medium | `DynamicNotchApp/Sources/HUDMonitor.swift:707` | One failed corebrightnessdiag read permanently turns off brightness and keyboard level reads until the app relaunches |
| 10 | medium | `DynamicNotchApp/Sources/LiveActivities/LiveActivitySelectionManager.swift:23` | Low-battery activity hides the FanControl safety alert |
| 11 | medium | `DynamicNotchApp/Sources/Support/NookWidgetGrid.swift:183` | pageStrip mounts every widget on every page, so widgets on hidden pages run their onAppear work (the Camera widget turns the camera on) |
| 12 | medium | `DynamicNotchApp/Sources/Support/WorkloadProfileCoordinator.swift:174` | Stale .workload claim kept during a manual pause hides power transitions, and the Power status line's Resume applies a workload profile whose rule no longer matches |
| 13 | medium | `DynamicNotchApp/Sources/Tray.swift:437` | Tray rename is not persisted, truncates multi-dot names, and renames the user's original file |
| 14 | medium | `FanControl/Sources/FanControlKit/FanProfileArbiter.swift:172` | Decisions blocked by isApplyAllowed are never applied when Fan Control is turned back on |
| 15 | medium | `FanControl/Sources/FanControlKit/FanProfileArbiter.swift:128` | A manual pick made while an automatic apply is in flight is ignored, and may be overwritten |
| 16 | medium | `FanControl/Sources/FanControlKit/FanProfileArbiter.swift:102` | After a relaunch the baseline is captured from the persisted active profile, which may be the one an automation applied |
| 17 | medium | `FanControl/Sources/FanControlKit/PowerProfileEngine.swift:167` | Persisted Low Power Mode memory is never restored after a relaunch when no rule asks for a value |
| 18 | medium | `FanControl/Sources/FanControlKit/PowerProfileEngine.swift:187` | Restore path clears the LPM memory before the helper write, so a failed restore loses the user's value for good |
| 19 | medium | `FanControl/Sources/FanControlKit/PowerProfileEngine.swift:175` | LPM restore flattens per-power-source settings: the engine reads the current-source state and writes it back with `pmset -a` |
| 20 | medium | `FanControl/Sources/FanControlXPC/LowPowerModeCommand.swift:130` | A slow Low Power Mode request can outlast the client's 8 s timeout and tear down the fan session |
| 21 | medium | `FanControl/Sources/FanControlXPC/LowPowerModeCommand.swift:18` | The helper can only write `pmset -a`, so restoring Low Power Mode overwrites the user's per-power-source setting |
| 22 | low | `DynamicNotchApp/Sources/AirPodsControlCenterDriver.swift:94` | The close loop toggles the Sound item based on an AXWindows count that lags behind, so it can reopen the menu it just closed |
| 23 | low | `DynamicNotchApp/Sources/AirPodsNoiseControl.swift:431` | A 'Read Current Mode' issued during the rate-limit wait replaces the in-flight set request, so the user's mode switch is dropped silently |
| 24 | low | `DynamicNotchApp/Sources/AirPodsNoiseControl.swift:357` | A failed or early system_profiler lookup is cached as -1 for the whole session, which hides the control for AirPods 4 (ANC) for good |
| 25 | low | `DynamicNotchApp/Sources/Automation/AutomationCommand.swift:113` | Built-in aliases shadow renamed custom profiles |
| 26 | low | `DynamicNotchApp/Sources/Automation/CommandRouter.swift:94` | widget/<id>/show ignores the new widget pages |
| 27 | low | `DynamicNotchApp/Sources/Automation/CommandRouter.swift:94` | widgetShow (URL scheme / dnctl / App Intent) opens the notch but never switches to the page that holds the widget |
| 28 | low | `DynamicNotchApp/Sources/CalendarManager.swift:234` | Deselecting every calendar shows all calendars |
| 29 | low | `DynamicNotchApp/Sources/CalendarWidgetView.swift:64` | Calendar widget only reloads when the count of today's events changes |
| 30 | low | `DynamicNotchApp/Sources/DisplayControlService.swift:422` | The read hold-off is measured from when the write was enqueued, so a slow refresh overwrites the slider with values read before the write |
| 31 | low | `DynamicNotchApp/Sources/DisplayControlService.swift:494` | A failed or vcp-less capabilities read is never cached, so it is repeated on every refresh and blocks the I/O queue |
| 32 | low | `DynamicNotchApp/Sources/DisplayControlService.swift:388` | The channel map is rebuilt on every refresh while any external display has no DDC endpoint |
| 33 | low | `DynamicNotchApp/Sources/DownloadsWatcher.swift:387` | 1 s polling during downloads re-sums large directories every tick and can keep running indefinitely |
| 34 | low | `DynamicNotchApp/Sources/HUDMonitor.swift:265` | Without Input Monitoring, the fallback key source is only a global monitor, which never receives events while DynamicNotch is the active app |
| 35 | low | `DynamicNotchApp/Sources/HUDMonitor.swift:118` | start() calls refreshPermissions() before the volume.onChange callback is installed, so the volume baseline is never seeded when Input Monitoring is already granted |
| 36 | low | `DynamicNotchApp/Sources/Support/NookWidgetGrid.swift:183` | Pages are identified by index and widgets by identity within a page only, so moving a widget across pages destroys and recreates its view during the drag |
| 37 | low | `DynamicNotchApp/Sources/Support/NookWidgetPager.swift:406` | edgeSide is never reset when a drag ends or is cancelled, so the edge-dwell page flip stops working on the next drag |
| 38 | low | `DynamicNotchApp/Sources/Support/NookWidgetPager.swift:512` | A claimed swipe whose .ended/.cancelled event never reaches this monitor leaves isSwiping true, so the notch can't close |
| 39 | low | `DynamicNotchApp/Sources/Support/WorkloadProfileCoordinator.swift:41` | Workload apply errors are read from arbiter.lastError right after setClaim, which may return before the apply runs; failed claims are never retried |
| 40 | low | `DynamicNotchApp/Sources/Tray.swift:560` | `updateLiveActivity` checks the filtered set, so a `.tray` request is never withdrawn while tray activities are disabled |
| 41 | low | `DynamicNotchApp/Sources/WidgetsSettingsTabView.swift:110` | The detail pane's Add/Remove from Nook edits `widgets` directly and leaves `widgetPages` out of date |
| 42 | low | `DynamicNotchApp/Tools/dnctl/main.swift:74` | dnctl turns a multi-word profile name into a path and the lookup fails |
| 43 | low | `FanControl/Sources/FanControlKit/ChargeLimitController.swift:140` | refresh() can overwrite the helper's newer read-back with an older SMC read |
| 44 | low | `FanControl/Sources/FanControlKit/PowerProfileEngine.swift:168` | lowPowerModeTarget is recorded before the write, so a failed LPM change is never retried while the rule stays matched |

## Details

### 1. timer/start crashes the app when the duration overflows Int

- Severity: high  ·  `DynamicNotchApp/Sources/Automation/AutomationCommand.swift:316`  ·  slice: automation-surface-f4
- Scenario: `open 'dynamicnotch://timer/start?minutes=1e300'` (or hours=1e16, or minutes=1e308 so that value*60 becomes +inf). Each value passes `value.isFinite && value >= 0`, but the product is never checked. `Int(total.rounded())` then traps ('Double value cannot be converted to Int') before the 1...maxTimerSeconds range check runs. Any local process can kill the app this way, and so can a web page once the browser's open-app prompt is accepted. Fix: check `total <= Double(maxTimerSeconds)` (and isFinite) before converting.
- Verification: The claimed crash is real. In `parseTimerStart` (AutomationCommand.swift:305–316), the code checks that each value is finite and not negative, but it never checks the scaled sum before calling `Int(total.rounded())` at line 316. Some examples:
- `minutes=1e300` gives 6e301, which is finite but well above `Int.max`.
- `minutes=1e308` makes `value*60` overflow to +inf.
- `hours=1e16` gives 3.6e19, also above `Int.max`.

In Swift, `Int(Double)` traps on any value outside Int's range or on a non-finite value. That happens before the `1...maxTimerSeconds` guard runs. The parser is reached from the URL scheme handler (CommandRouter.swift:57, `AutomationCommand.parse(url)`), so any `open dynamicnotch://timer/start?minutes=1e300` kills the app. The impact is a local denial of service (the app crashes) with no privilege gain, so the severity is medium.
- Suggested fix: Before converting, check the range on the Double. In AutomationCommand.swift, replace line 316 with:

    guard total.isFinite, total.rounded() >= 1, total.rounded() <= Double(maxTimerSeconds) else {
        return .failure(.invalidArgument(name: "duration", value: "\(raw-ish total) s (1 s – 23:59:59)"))
    }
    let seconds = Int(total.rounded())

(For example, use `String(format: "%g", total)` for the message.) Alternatively, add `guard total.isFinite, total < Double(maxTimerSeconds) + 1 else { return .failure(...) }` just before the `Int(...)` conversion.

### 2. Sound menu is left open when AXPress on the menu extra returns an error, because the `defer { close(...) }` is registered only after the press succeeds

- Severity: medium  ·  `DynamicNotchApp/Sources/AirPodsControlCenterDriver.swift:40`  ·  slice: hud-airpods-f5-f7
- Scenario: AXPress on a menu-bar extra often returns kAXErrorCannotComplete or a timeout while the menu is still opening; the 1 s messaging timeout makes this more likely. The press does open the menu, but `guard Self.press(soundItem) else { return .failure(.menuDidNotOpen) }` returns before the `defer` exists. So the Sound menu stays open on screen and the widget shows 'The Sound menu did not open'. Moving the defer above the press, or closing whenever the window count has gone up, fixes it.
- Verification: This is real but low severity. In `perform()` (AirPodsControlCenterDriver.swift:39-41), `baseline` is taken first. Then `guard Self.press(soundItem) else { return .failure(.menuDidNotOpen) }` runs, and only after it does `defer { close(...) }` get registered. `press` just checks that `AXUIElementPerformAction(...) == .success`. AXPress can return an error such as kAXErrorCannotComplete when the target app is slow to reply within the messaging timeout (here set to 1 s on the Control Center app element), even though the action still goes through. When that happens, the Sound menu opens but the function returns before the defer exists. The menu is left open and the widget reports "menuDidNotOpen". This breaks the file's own rule, stated in step 5 of its header: "Always close the menu". `close()` already does nothing when the window count has not gone up, so registering it before the press costs nothing. How often a press reports an error but still works was not checked on the device.
- Suggested fix: Register the close before pressing:

    let baseline = Self.windows(of: cc).count
    defer { close(soundItem, cc: cc, baseline: baseline) }
    guard Self.press(soundItem) else { return .failure(.menuDidNotOpen) }

`close()` already sleeps 0.15 s and only presses while `windows(of: cc).count > baseline`, so it does no harm when the menu never opened. It also catches a menu that opens late after the press reported an error.

### 3. close() checks the window count only once (after 0.15 s), so a menu that opens after openTimeout is never closed

- Severity: medium  ·  `DynamicNotchApp/Sources/AirPodsControlCenterDriver.swift:91`  ·  slice: hud-airpods-f5-f7
- Scenario: Control Center is slow (first use after login, or under load) and the menu window appears 1.3–1.5 s after the press. waitFor (1.2 s) fails with .menuDidNotOpen. The deferred close sleeps 0.15 s, sees count == baseline, never enters its loop and returns. The menu then appears and stays open.
- Verification: This is a real defect, but low severity. I read caf55c0:DynamicNotchApp/Sources/AirPodsControlCenterDriver.swift.

How the code runs:
- `perform` presses the Sound item. The press must succeed, otherwise the function returns before the `defer` is set up.
- It then calls `waitFor(openTimeout = 1.2 s)`. When that runs out it returns `.failure(.menuDidNotOpen)`, and the deferred `close` runs.
- `close` (lines 91–98) sleeps once for 0.15 s. It then checks `while windows.count > baseline`, and that is the only point where it looks for a menu. If the menu window has not appeared yet, the count still equals `baseline`, the loop never runs, and `close` returns.

The failure: AXPress was accepted, but Control Center only shows the menu window more than about 1.35 s after the press (slow first use after login, or the system under load). In that case nothing ever closes it. The Sound menu stays open on screen, and the request is reported as "menu did not open". This breaks the documented rule "Always close the menu" (header comment, step 5).

Why the impact is small: the menu is only left open until the user clicks somewhere else. There is no data loss and no unwanted output switch. The timing window is also narrow: the menu has to arrive after about 1.35 s.
- Suggested fix: In `close`, first wait a grace period for a late menu, and only then run the existing close loop. For example, pass whether the menu was seen to open (`close(soundItem, cc: cc, baseline: baseline, opened: Bool)`, setting `opened` once `waitFor` succeeds). If `opened` is false, poll `Self.windows(of: cc).count > baseline` for up to about 1.0 s (`_ = waitFor(timeout: 1.0) { Self.windows(of: cc).count > baseline ? true : nil }`). After that, run the existing 0.15 s sleep and the press/retry loop. A simpler alternative is to replace the single 0.15 s check with a loop that runs until a deadline of about 1.5 s: press whenever count > baseline, and stop once the count is back at baseline after a press, or when the deadline passes.

### 4. capture/screen lets any process get a full-screen screenshot under DynamicNotch's Screen Recording grant

- Severity: medium  ·  `DynamicNotchApp/Sources/Automation/CommandRouter.swift:99`  ·  slice: automation-surface-f4
- Scenario: `capture/screen` runs `screencapture -m` with no interaction and no check that the Capture widget is in the Nook. A sandboxed app with no Screen Recording permission can open `dynamicnotch://capture/screen` and, when the Capture destination is Clipboard (`-c`), read NSPasteboard.general a moment later. That gives it the whole main display, captured under DynamicNotch's TCC grant (and ClipboardHistoryManager also records the image). A web page can do the same once the browser prompt is allowed. Fix: limit URL captures to the interactive kinds (area/window), or require confirmation, or never send URL-triggered captures to the clipboard.
- Verification: I read the code and the claim holds. Any process can open a `dynamicnotch://` URL, and nothing checks who sent it: URLCommandRouter.handle only checks the scheme, then calls CommandRouter.perform. For `.capture(kind)`, CommandRouter.swift:98-101 only checks `isCaptureIdle`. Unlike keepAwake and pomodoro, it does not check that the widget is in the Nook, and it asks for no confirmation. LiveAutomationActions.capture calls CaptureManager.start, which waits for the configured delay (0 by default) and then launches `/usr/sbin/screencapture -m`. That is non-interactive, adds `-x` if sounds are off, and adds `-c` when the destination is `.clipboard` (CaptureManager.swift:220, 227). TCC charges the capture to DynamicNotch, the responsible process. So an app without Screen Recording permission, including a sandboxed one, can open `dynamicnotch://capture/screen` and read NSPasteboard.general a moment later. That gives it the whole main display, and ClipboardHistory keeps a copy too. With the default Desktop destination, the leak only reaches apps that can read ~/Desktop, so the clipboard case is the real exposure. It needs the user to have chosen Clipboard and granted Screen Recording. It is a genuine confused-deputy hole on an unauthenticated command surface. Severity: medium (personal-use app, but it bypasses a privacy permission without the user knowing).
- Suggested fix: In CommandRouter.perform `.capture(let kind)`: reject the non-interactive kind when the request comes from outside, e.g. `if kind == .screen { return .failure(.failed("Full-screen capture is not available from URLs.")) }`. Area and window stay allowed because they need the user to click. Also add the same Nook check the other widgets have: `guard actions.nookWidgets.contains(.capture) else { return .failure(.widgetNotInNook(NookWidget.capture.name)) }`. To keep `capture/screen` for the user's own App Intents/dnctl, pass a source flag (url vs intent) into perform and apply the `.screen` block only to `.url`. Or, for URL-triggered shots, force the output to a file instead of `.clipboard`.

### 5. Fan commands fail with 'No fans found' whenever monitoring has not polled yet

- Severity: medium  ·  `DynamicNotchApp/Sources/Automation/LiveAutomationActions.swift:38`  ·  slice: automation-surface-f4
- Scenario: When 'auto-start monitoring' is off, or on a cold launch from a URL or intent (startMonitoring/refreshNow poll asynchronously), `FanControlManager.shared.fans` is still empty. `profile/boost` and `fan/auto` then return `.noFans` and beep, even though `applyProfile` would start monitoring by itself. In the auto-start-off case a Shortcut 'Set Fan Profile' never works until the user opens the Fan Control UI. Fix: start monitoring and wait for the first discovery (or a refresh) before deciding there are no fans.
- Verification: Confirmed. `LiveAutomationActions.applyFanProfile` (line 38) returns `.noFans` straight away when `FanControlManager.shared.fans` is empty. The only call that makes the manager discover fans is in `FanControl-Patches.applicationDidFinishLaunching`, and it runs only when `isEnabled && autoStartMonitoring`. Otherwise discovery waits for the Nook hooks or the settings pane to start monitoring. Nothing on the automation path calls `startMonitoring()` or `refreshNow()`. So with "Start Monitoring at Launch" off (default is on), every URL or Shortcut fan command (`profile/*`, `fan/auto`) fails with "No fans found" until the user opens the Fan Control UI. Even with auto-start on, `startMonitoring()` only queues the first poll (`poller.enqueue`), so a URL or intent that arrives with the cold launch can hit an empty `fans` and fail the same way. Removing the guard alone would not fix it: `planApply` uses the poller's `polledFans`, which is empty until a poll has run, so the plan would contain no writes. Severity: medium. It is a functional failure, not a safety problem; it hits a non-default setting or a launch race.
- Suggested fix: In `applyFanProfile`, before the `.noFans` guard, make sure fans have been discovered and wait briefly for the first poll:
```swift
let manager = FanControlManager.shared
if manager.fans.isEmpty {
    if !manager.isMonitoring { manager.startMonitoring() } else { manager.refreshNow() }
    for _ in 0..<20 where manager.fans.isEmpty {   // up to ~2 s
        try? await Task.sleep(for: .milliseconds(100))
    }
}
guard !manager.fans.isEmpty else { return .failure(.noFans) }
```
(Alternatively, call `refreshNow()` without `startMonitoring()` if read-only monitoring should stay off. A manual profile starts monitoring anyway in `FanController.apply`.) A cleaner fix is an awaitable `FanControlManager.ensureDiscovered()` that awaits a poll on the poller.

### 6. fan/auto never does anything once Automatic is the active profile

- Severity: medium  ·  `DynamicNotchApp/Sources/Automation/LiveAutomationActions.swift:39`  ·  slice: automation-surface-f4
- Scenario: The short-circuit `profile.id == activeID && (isSMCWriteSessionOpen || id == automatic)` always succeeds for Automatic, so `fan/auto` and the 'Return Fans to Automatic' intent report 'Automatic is already active' without writing anything. The intent promises to 'hand every fan back to the system's automatic control', but unlike the widget's Return to Automatic it never calls `restoreDefaultControl()`. Fans that are still manual, or a write session that is still open (e.g. after a failed apply rolled the selection back to Automatic), are left as they are. Fix: route .fanAutomatic to `FanControlManager.restoreDefaultControl()`.
- Verification: Confirmed. `CommandRouter.perform(.fanAutomatic)` (CommandRouter.swift:70) only calls `actions.applyFanProfile(.builtIn(.automatic))`. In LiveAutomationActions.swift:39 the early return `profile.id == activeID && (isSMCWriteSessionOpen || id == automatic)` is always true for Automatic once it is the active profile, and `activeID` also falls back to Automatic when nothing is selected. So `fan/auto` and ReturnFansToAutomaticIntent ("Hands every fan back to the system's automatic control") just report "Automatic is already active" and write nothing.

The widget/pane button instead calls `FanControlManager.restoreDefaultControl()` (FanController.swift:154). That function opens a session when the SMC reports orphaned manual fans, writes all-automatic with force, and closes the session.

Cases this misses:
- **Fans forced manual elsewhere:** another tool such as FanFi, or a killed helper session, left fans manual while Automatic is selected.
- **Session left open:** a failed apply rolled the selection back to Automatic (`ProfileSelectionRollback.undo`) but left the write session open. Nothing in that path closes it, so the helper keeps it.

In both cases the automation does nothing, while the identically named UI action recovers. Severity is low to medium: there is no crash or unsafe write, but the action does not do what it promises in exactly the recovery cases it exists for. Even without the early return, `FanControlProfiles.apply(automatic)` would write nothing when no session is open (FanController.apply), and it would not close an open session. So removing the short-circuit alone is not enough.
- Suggested fix: Add `func returnFansToAutomatic() async -> AutomationOutcome` to AutomationActions. In LiveAutomationActions (canImport(FanControlKit)): `guard !FanControlManager.shared.fans.isEmpty else { return .failure(.noFans) }; do { try await FanControlManager.shared.restoreDefaultControl(); return .success("Returned fans to automatic") } catch { return .failure(.failed(error.localizedDescription)) }`. In the #else branch return `.failure(.fanControlUnavailable)`. In CommandRouter.swift:70 change the `.fanAutomatic` case to `if let error = fanPrecondition() { return .failure(error) }; return await actions.returnFansToAutomatic()`. Leave the short-circuit in applyFanProfile as it is for `fan/profile automatic`, or limit it to non-Automatic profiles.

### 7. CalendarManager's access status and today's events go stale when access is granted through PermissionCenter or System Settings

- Severity: medium  ·  `DynamicNotchApp/Sources/CalendarManager.swift:73`  ·  slice: refactor-crosscut
- Scenario: `authorizationStatus` is only re-read by `refreshAuthorizationStatus()` (in the onAppear of NextUpWidgetView, CalendarWidgetView and CalendarWidgetSettingsView) and by `requestFullAccess()`. When access was denied, the new PermissionStatusRow's "Open System Settings" button calls `PermissionCenter.openSystemSettings`. The user turns calendar access on and returns to the app. PermissionCenter refreshes on didBecomeActive, but CalendarManager does not. The Calendar pane keeps showing "Calendar access is off", `NextUpManager.hasAccess` stays false, so Next Up refreshes return nothing, and Next Up's 60 s tick cannot recover by itself. Even after `refreshAuthorizationStatus()` runs, it loads the calendars but never calls `scheduleRefresh()`, so `events` stays empty. The calendar live activity then does not appear until an EKEventStoreChanged notification or midnight.
- Verification: The claim holds, at low-to-medium severity. `CalendarManager.authorizationStatus` is set at init and re-read only by `refreshAuthorizationStatus()`, which is called from `requestFullAccess()` and from the `onAppear` of NextUpWidgetView, CalendarWidgetView and CalendarWidgetSettingsView. CalendarManager has no observer for didBecomeActive or for `PermissionCenter.didChangeNotification`. PermissionCenter does refresh its own `.calendar` status on didBecomeActive and on EKEventStoreChanged, but nothing passes that on to CalendarManager; only HUDMonitor and AudioDevicesManager observe it.

When access is denied, CalendarWidgetSettingsView shows `PermissionStatusRow.calendars`. Its denied-state button is "Open System Settings", which by default calls `PermissionCenter.shared.openSystemSettings(for:)` (PermissionStatusRow.swift:110-111). The `allow` closure is used only in `.notDetermined`. So after the user turns access on and comes back, the settings pane that is still showing keeps "Calendar access is off", because its `onAppear` does not fire again.

When `refreshAuthorizationStatus()` does run later, for example when the notch widget tree is rebuilt, it updates the status and calls `loadSelectedCalendars()` but never `scheduleRefresh()`. `events` therefore stays as the empty result fetched without access. CalendarLiveActivity reads `CalendarManager.shared.events`, so it shows nothing until an EKEventStoreChanged or NSCalendarDayChanged notification arrives. Only the `requestFullAccess()` path reloads events.

Two parts of the scenario are weaker than claimed:
- Next Up does recover once the notch is opened, because NextUpWidgetView's `onAppear` calls `refreshAuthorizationStatus()` and then `manager.refresh()`.
- The per-day lists in CalendarWidgetView reload because of `.onChange(of: authorizationStatus)`.

The stale settings pane and the stale `events` / calendar live activity are real defects.
- Suggested fix: In CalendarManager:

1. In `refreshAuthorizationStatus()`, detect when access has just been granted and reload:
```swift
let wasGranted = hasReadAccess
let status = EKEventStore.authorizationStatus(for: .event)
if status != authorizationStatus { authorizationStatus = status }
if hasReadAccess && selectedCalendars.isEmpty { loadSelectedCalendars() }
if hasReadAccess != wasGranted {
    invalidateDayCache()
    scheduleRefresh()
    NextUpManager.shared.refresh()
}
```

2. In `init`, subscribe to PermissionCenter so CalendarManager follows permission changes made outside the app:
```swift
observers.append(PermissionCenter.shared.observe([.calendar]) { _, _ in
    CalendarManager.shared.refreshAuthorizationStatus()
})
```
Alternatively, add a `NSApplication.didBecomeActiveNotification` observer that calls `refreshAuthorizationStatus()`.

### 8. A Clear Old plan can appear after the user cancelled it and is never re-checked on confirm

- Severity: medium  ·  `DynamicNotchApp/Sources/DownloadsWatcher.swift:665`  ·  slice: displays-downloads-usage-f6-f8-f10
- Scenario: prepareClear() runs oldItems on the scan queue, and directorySize can walk up to 20k entries per old folder, so this takes a while. If the notch closes meanwhile, onDisappear calls cancelClear(), then the async completion sets w.clearPlan = plan with no check that the request is still current (no generation/token check, no check that the widget is still shown or still on the same folder). The next time the widget opens, perhaps hours later, it shows the old confirmation. confirmClear() then recycles plan.urls exactly as listed: it does not re-check that each URL is still old, is not partial/in progress, and is still the same file. If an old file was deleted and a new download with the same name arrived in the meantime, the new download goes to the Trash. This also happens when the watched folder is changed while the plan is being prepared, because apply() clears clearPlan before the late completion fills it again.
- Verification: The defect is real, medium severity. I checked DownloadsWatcher.swift:654-685 and DownloadsWidgetView.swift:105-110. prepareClear() posts its result back to the main queue and sets `isPreparingClear = false; clearPlan = plan` without checking anything first. There is no token or generation check and no `w.folder == folder` check, although autoClearIfDue does check the folder. cancelClear() only sets clearPlan to nil and does nothing to stop a scan already in flight.

So the sequence goes like this: the user picks "Clear Old Items…", then closes the notch before the scan finishes. onDisappear calls cancelClear(), which does nothing because the plan isn't set yet. The late completion then sets clearPlan. tearDown doesn't clear clearPlan, so it stays set. The next time the widget appears, `if let plan = clearPlan` shows the confirmation the user had already dismissed. confirmClear() then recycles plan.urls exactly as listed when the scan ran, without checking them again.

The folder-change case works the same way: apply() sets clearPlan to nil, but a late completion fills it again with a plan for the previous folder. The case where a new download arrives under the same name is narrower but follows from the same missing re-check. The plan hides behind a dismissed UI and resurfaces later, so this is wrong behaviour that can move files to the Trash, not a style issue.
- Suggested fix: Add a private clearToken counter (with @ObservationIgnored, like the other private state). Increment it in cancelClear(), in tearDown(), and in apply() where clearPlan is set to nil. In prepareClear(), capture `let token = clearToken` and `folder` before dispatching. In the completion, always set isPreparingClear = false, then `guard token == w.clearToken, w.folder == folder else { return }` before setting w.clearPlan. In confirmClear(), check the plan again before recycling: `let fresh = Set(Self.oldItems(in: folder, days: plan.days, now: Date()).urls)` and pass `plan.urls.filter(fresh.contains)` to recycle(), so files that are no longer old, or are now partial or replaced, are left alone. Ideally run that re-check on scanQueue, the same way autoClearIfDue does.

### 9. One failed corebrightnessdiag read permanently turns off brightness and keyboard level reads until the app relaunches

- Severity: medium  ·  `DynamicNotchApp/Sources/HUDMonitor.swift:707`  ·  slice: hud-airpods-f5-f7
- Scenario: `if snapshot == nil { self.disabled = true }` treats every nil the same: the 2 s timeout (SIGTERM gives terminationStatus 15), a non-zero exit, or a plist without the built-in values. If the seed read at launch is slow during login (start() calls levelRead.request() at once) or one key press hits a busy system, request() returns early from then on. The HUD shows direction chevrons only and Settings shows 'level unknown' for the rest of the session. Only a missing tool should disable reads; transient failures should retry or back off.
- Verification: The claim holds. HUDMonitor.swift:104 creates `HUDLevelReadScheduler` once per monitor, and nothing ever sets `disabled` back to false. In `run()` (line ~707), any nil result from `HUDCoreBrightness.read()` sets `disabled = true`. That nil can come from a missing tool, a failed `process.run()`, the 2 s timeout (SIGTERM gives a non-zero terminationStatus), any non-zero exit, or a plist that `parse()` finds no built-in display or keyboard values in. After that, every `request()` (the seed read at line 158 and the key-press reads at 312/328) returns at once. One slow read, for example the seed read during a busy login, therefore turns off brightness and keyboard levels until the app relaunches, and the HUD shows direction chevrons only. Severity is low to medium: it degrades a feature, with no crash and no safety impact.
- Suggested fix: Disable reads for good only when the tool is missing, and treat every other failure as transient. For example, check `FileManager.default.isExecutableFile(atPath: HUDCoreBrightness.toolPath)` in `request()` (or once in init) and set `disabled` only when that check fails. In `run()`, replace `if snapshot == nil { self.disabled = true }` with a failure counter or backoff, such as `failures += 1; if failures >= 5 { cooldownUntil = .now + 60 }`, and reset `failures` to 0 on success. Then `request()` skips reads only while the cooldown is active, so the next key press after it ends tries again.

### 10. Low-battery activity hides the FanControl safety alert

- Severity: medium  ·  `DynamicNotchApp/Sources/LiveActivities/LiveActivitySelectionManager.swift:23`  ·  slice: refactor-crosscut
- Scenario: The Mac is unplugged at 15% with the low-power alert on, so `.battery` stays requested. The SMC then crosses the alert threshold and FanControlAlertCoordinator inserts `.fanAlert` (priority 100, gate `.always`). `selectActivity` only exempts `.hud`. The battery rule (`!isCharging && contains(.battery)`) returns `.battery`, so the overheating or fan-stalled warning never reaches the closed notch for as long as the battery stays low. The fan alert should beat the battery rule, as `.hud` already does. (This was also true before the refactor; the descriptor table did not fix it.)
- Verification: The defect is real, medium severity, and it was there before the refactor. In `LiveActivitySelectionManager.swift`, line 22 lets only `.hud` skip the battery rule. Line 23 then returns `.battery` whenever the Mac is on battery and `.battery` is requested. In `BatteryLiveActivity.handle`, `.battery` stays inserted the whole time the battery is not charging, at or below `lowBatteryThreshold`, with `lowPowerAlert` on. So when FanControlAlertCoordinator inserts `.fanAlert` (priority 100, gate `.always`) through `insertSync`, `LiveActivityCenter.currentActivity` still shows `.battery`, and the overheating or fan-stalled warning never appears in the closed notch until the user plugs in or the battery rises. I found no other place in the app that shows the fan alert (no notification or sound). This breaks the promise of the `.always` gate that a safety alert is always shown, and the fan alert's own top priority.
- Suggested fix: In `selectActivity`, let `.fanAlert` beat the battery rule too. Replace line 22 with:
```swift
let top = activitiesByPriority.first { activeActivities.contains($0) }
if let top, top == .hud || top.descriptor.priority > LiveActivity.battery.descriptor.priority { return top }
```
That compares by priority. Alternatively, check `.fanAlert` explicitly inside `#if canImport(FanControlKit)` and return it whenever `activeActivities` contains it, before the `.hud` and battery checks.

### 11. pageStrip mounts every widget on every page, so widgets on hidden pages run their onAppear work (the Camera widget turns the camera on)

- Severity: medium  ·  `DynamicNotchApp/Sources/Support/NookWidgetGrid.swift:183`  ·  slice: pages-registry-f9
- Scenario: Pages = [[calendar, media], [mirror]] and Camera 'Open camera automatically' is on. The user opens the notch on page 1. MirrorWidgetView on page 2 sits off-screen in the HStack strip, but its onAppear still fires and calls startCamera(). The camera LED comes on and frames are captured while the camera is not visible. Every other off-page widget's onAppear samplers and monitors also keep running.
- Verification: Confirmed in the code. `pageStrip` (NookWidgetGrid.swift:179-195) puts every page in an `HStack` through `ForEach(geo.pages.indices)` and only moves it sideways with `.offset`. Nothing is unmounted or made conditional, so every widget on every page is built and gets `onAppear` whenever the notch opens. `MirrorWidgetView.onAppear` (MirrorWidgetView.swift:165-173) calls `startCamera()` when `settings.autoOpen && authorization == .authorized && hasCamera`. It never checks whether its page is the one on screen. The camera is only stopped in `onDisappear`, which runs when the whole grid closes, not when the user changes page. Result: with Camera on page 2 and auto-open enabled, opening the notch on page 1 turns the camera and its LED on while the camera can't be seen. Severity: medium, a privacy problem from the camera running unseen. The second half of the claim is not a defect. The other widgets' samplers are managed by `WidgetPresence`, which by design keeps them running whenever the widget is anywhere in the Nook layout, so off-page widgets keeping them alive is intended behaviour.
- Suggested fix: Pass the page's visibility down through the environment and gate the camera on it. Add `EnvironmentValues.nookWidgetPageIsCurrent: Bool` (default true). In `pageStrip`, apply `.environment(\.nookWidgetPageIsCurrent, p == geo.current)` to each `page(...)`. In `MirrorWidgetView`, read `@Environment(\.nookWidgetPageIsCurrent) var isCurrentPage`. In `onAppear`, require `isCurrentPage` before auto-starting. Add `.onChange(of: isCurrentPage)`: when it becomes false, do what `onDisappear` does (set mode to `.inactive`, clear `session`, call `stopCamera()`). When it becomes true and `autoOpen`, authorization and `hasCamera` all hold, call `startCamera()`.

### 12. Stale .workload claim kept during a manual pause hides power transitions, and the Power status line's Resume applies a workload profile whose rule no longer matches

- Severity: medium  ·  `DynamicNotchApp/Sources/Support/WorkloadProfileCoordinator.swift:174`  ·  slice: arbiter-power-workload
- Scenario: Xcode rule → Boost is engaged. The user picks Quiet by hand, so the engine pauses and the coordinator keeps the claim. The user quits Xcode. While paused, the engine never withdraws the claim (with 'Pause Until Resumed' it never does). Power-rule transitions (unplugging, for example) no longer change automaticWinner, so they neither end the manual override nor take effect. If the user clicks 'Resume' in the Power Profiles status line, the arbiter applies Boost for an app that is no longer running. Turning workload automation off while paused withdraws the claim and ends the user's manual override as a side effect.
- Verification: This is a real bug. I traced it through the code:
- WorkloadProfileCoordinator.evaluate (lines 174-175) leaves `currentClaim` and the arbiter's `.workload` claim unchanged while the status is `.pausedByManualSelection`.
- While a ManualLock exists, WorkloadProfileEngine.update returns early with the paused status and never moves to `.idle`/`disengage()`. With manualOverrideMinutes == 0 ("Pause Until Resumed") nothing clears the lock except an in-engine resume(), a disable, or a reset.
- So after Xcode quits, `claims[.workload]` is still Boost. ProfileArbitration.automaticWinner checks emergency > workload > power, so a change to the power claim does not change automaticWinner. That means setClaim(...) for `.power` never ends the manual override (manualEndsOnTransition does not fire) and the power rule never becomes the winner.
- The "Resume" button in FanControlPowerProfileStatusLine calls PowerProfileEngine.resumeAutomation → FanProfileArbiter.resumeAutomation. That clears manualProfileID and runs reconcile(). decision then equals automaticWinner, which is the stale workload Boost claim, and the arbiter applies Boost for an app that is no longer running. The workload engine is still paused, so nothing withdraws that claim (with "Pause Until Resumed", never). The fans stay at Boost until the user resumes workload automation or turns it off.
- Turning workload automation off while paused: update() returns `.disabled`, so sendClaim(nil) withdraws the claim. automaticWinner changes from Boost to the power claim (or nil), and ProfileArbitration.setClaim clears manualProfileID, which ends the user's manual pick as a side effect. This is also confirmed.

Severity is medium. The result is the wrong profile (louder fans, power rules ignored), not a safety problem; the 95 °C emergency override still works below this layer.
- Suggested fix: While paused, withdraw the stale workload claim without ending the arbiter's manual override:
1. Add a flag to `ProfileArbitration.setClaim`: `setClaim(_:for:endsManualOverride: Bool = true)`. When it is false, skip the `manualProfileID = nil` step.
2. Add the same flag to `FanProfileArbiter.setClaim` and pass it through.
3. In `WorkloadProfileCoordinator.evaluate`, change the `.pausedByManualSelection` case so it no longer keeps the claim: if `currentClaim != nil`, set `currentClaim = nil` and call `arbiter.setClaim(nil, for: .workload, endsManualOverride: false)`. Do this through the serialized claimTask path, for example by adding a `preserveManual` parameter to `applyWorkloadProfile`.
4. Keep `.heldForEmergency` as it is.

After this, a power transition during the pause updates automaticWinner normally and ends the manual override as designed. Power "Resume" applies the power rule's profile instead of the stale Boost. When the pause ends, the existing `.engaged` path re-claims with `endManualOverride: wasPaused` only if a rule still matches.

### 13. Tray rename is not persisted, truncates multi-dot names, and renames the user's original file

- Severity: medium  ·  `DynamicNotchApp/Sources/Tray.swift:437`  ·  slice: refactor-crosscut
- Scenario: With "Keep files after quit" on, the user renames a tray item. `rename()` moves the file on disk but never calls `filesDidChange()`, so trayState.json keeps the old URL. On the next launch `loadPersistedFiles` logs "tray file no longer exists" and drops the item, leaving an orphaned copy in Caches/TrayFiles. `TrayFile.rename(to:)` also keeps only the text before the first ".", so typing "report.v2.pdf" produces "report.pdf" (or fails if that name exists). With Copy files off, the file renamed is the user's original.
- Verification: I read the code and the claim holds. In Tray.swift:437, `rename()` calls `editing.file.rename(to:)` and then clears `editingFile`. It never calls `filesDidChange()`/`persist()`. `persist()` is only reached through the `files` setter, `addFile`, and the Keep-files toggle in TraySettingsView. Nothing saves the tray on quit. So with "Keep files after quit" on, trayState.json still holds the pre-rename URL until some unrelated tray change happens. On the next launch, `loadPersistedFiles` finds no file at that URL, logs "tray file no longer exists" and drops the item, while the renamed copy stays orphaned in Caches/TrayFiles/<UUID>/.

The name truncation is also real: TrayFile.swift:75 uses `newName.components(separatedBy: ".").first` and then re-appends the old extension. Typing "report.v2.pdf" gives "report.pdf". If that name already exists, the move fails, and the error is swallowed by `try?`.

With copyFiles off, `TrayFile.url` is the user's original file, so `moveItem` renames it in place. That is surprising, but it follows from the by-reference design, so it is the weakest part of the claim.

The code came in with 93b60a7, which is inside the refactor range. Severity: medium, because the tray item is silently lost after a relaunch.
- Suggested fix: In Tray.swift `rename()`: `do { try editing.file.rename(to: editing.newName); filesDidChange() } catch {}`, then `editingFile = nil`. In TrayFile.rename(to:): stop splitting on the first "." and keep the full typed name. For example: `let typedExt = (newName as NSString).pathExtension; let newURL = url.deletingLastPathComponent().appendingPathComponent(typedExt.isEmpty && !url.pathExtension.isEmpty ? newName + "." + url.pathExtension : newName)`, and return early if `newURL == url`. Optionally, when `copyFiles` is off (by-reference items), either block renaming or ask before renaming the original file.

### 14. Decisions blocked by isApplyAllowed are never applied when Fan Control is turned back on

- Severity: medium  ·  `FanControl/Sources/FanControlKit/FanProfileArbiter.swift:172`  ·  slice: arbiter-power-workload
- Scenario: With the Fan Control master switch off, a power rule or workload claim arrives: reconcile returns at the isApplyAllowed guard. The user turns Fan Control back on. Nothing calls reconcile or retry: later power ticks and workload evaluations send identical claims, and setClaim returns false. The matching profile is not applied until the next rule transition.
- Verification: Confirmed at caf55c0. `FanProfileArbiter.reconcile()` (line 172) returns early when `isApplyAllowed` is false, and nothing remembers that a decision is still waiting. The gate is installed in `FanControlPowerProfiles.start()` as `{ general.isEnabled }`. `PowerProfileEngine` does not look at the Fan Control switch: every evaluation sends the same `.power` claim again. `ProfileArbitration.setClaim` returns false for a claim identical to the one it holds (`claims[layer] != claim`), so `reconcile` is never reached. The only other entry points are `retry()` and `resumeAutomation()`, and a grep finds no caller of either when the feature is turned on. The enable path in `FanControlGeneralTabView` only calls `manager.startMonitoring()`, which re-applies the persisted active profile and not the arbiter's decision.

The scenario happens in two cases:
- The app launches with Fan Control off, the active profile is X, and a power rule claims Y. The user then enables Fan Control.
- The active profile is already Automatic, so turning Fan Control off does not change `activeProfileID`, `restoreDefaultControl` causes no manual-selection note, and a power rule claims Y while the feature is off.

In both cases the decision says Y, the active profile is X or Automatic, and Y is applied only at the next rule transition.

One thing limits the impact. When the toggle is turned off with a non-Automatic profile active, `restoreDefaultControl` sets Automatic and the arbiter records that as a manual selection, which wins anyway. Workload claims are not affected: `WorkloadProfileCoordinator` withdraws its claim while the feature is off and sends a new one when it is back on, which is a real transition. So the defect is the power layer only, with low-to-medium severity: wrong behaviour (the profile is not applied), with no safety impact.
- Suggested fix: When Fan Control turns back on, re-run the arbiter. In `FanControlGeneralTabView.isEnabled` (enabled branch), after `manager.startMonitoring()`, add `Task { await FanProfileArbiter.shared.retry() }`. A more central option: in `FanControlPowerProfiles.start()`, subscribe to `SettingsStore` updates for `.fanControlGeneralSettings` and call `await FanProfileArbiter.shared.retry()` on each false→true change of `isEnabled`. That also covers automation/URL-scheme paths that set the flag. Another option is to keep a `pendingWhileDisallowed` flag in the arbiter, set at the `isApplyAllowed` guard, and expose `applyAllowedDidChange()`, which calls `reconcile()` when the flag is set.

### 15. A manual pick made while an automatic apply is in flight is ignored, and may be overwritten

- Severity: medium  ·  `FanControl/Sources/FanControlKit/FanProfileArbiter.swift:128`  ·  slice: arbiter-power-workload
- Scenario: The arbiter applies Boost, which awaits openSession or helper XPC for a few seconds, so isApplying is true. Meanwhile the user picks Quiet in the widget. activeProfileDidChange returns early on isApplying, and after the loop lastObservedActiveID is re-synced to the current value. The pick is never classified as manual: no manualSelectionNotification, so the workload engine does not pause, and the status shows the rule instead of 'Manual'. Depending on ordering, the arbiter's later select can also silently replace Quiet with Boost.
- Verification: This one is real. The code paths are in FanProfileArbiter.swift (lines 125–135 and 170–189) and FanController.apply (lines 219–254).

1. `reconcile()` sets `isApplying = true` and then awaits `host.applyFanProfile`. Inside that call, `FanController.apply` may first await `openSession()` (the helper handshake, which can take seconds). Only after that does it select the profile (`activeProfileID = profile.id`), and then it awaits the poller writes.
2. If the user picks Quiet in this window, the manager's own `applyProfile` selects Quiet and the observation callback fires. `activeProfileDidChange()` copies Quiet into `lastObservedActiveID` and returns at `guard !isApplying`. Nothing calls `noteManualSelection`, nothing posts `manualSelectionNotification`, and `lastAutomaticApplyID` keeps the Boost id.
3. At the end of the loop, `lastObservedActiveID = host.activeFanProfileID` overwrites the value with no classification.

The result: the arbitration stays on the automatic winner, the workload engine is never told to pause (it filters by `isApplying` and `lastAutomaticApplyID`), and the status shows the rule instead of Manual.

There are two ways it goes wrong, depending on ordering:
- **User's pick lands during the arbiter's `openSession` await:** the arbiter's later `select(Boost)` silently replaces Quiet.
- **User's pick lands after the arbiter's select:** Quiet stays active, but the arbiter believes Boost was applied. The next claim change re-applies the automatic decision over the user's choice, even though manual should outrank every layer.

A rollback after a failed arbiter apply can also undo the user's selection.

Severity: medium. It is a precedence violation (manual > automatic is broken). It is not a safety issue, because the SMC is still written with a valid profile.
- Suggested fix: Classify changes during an apply instead of dropping them. In `activeProfileDidChange()`, replace `guard !isApplying else { return }` with:
`if isApplying && (current == lastAutomaticApplyID || current == preApplyActiveID) { return }`
Here `preApplyActiveID` is a new stored property that `reconcile()` sets to `host.activeFanProfileID` just before `isApplying = true`. That lets the arbiter's own select and its rollback through, while any other id goes on to `noteManualSelection` and the notification.

Also, at the end of each loop iteration in `reconcile()`, replace the bare `lastObservedActiveID = host.activeFanProfileID` with a check. If the current id is neither `decision.profileID` (on success) nor `preApplyActiveID` (on failure), call `activeProfileDidChange()` after setting `isApplying = false`, so the pick is classified as manual and `reconcileAgain` is stopped from re-applying over it.

The arbiter's late `select` still overwrites a pick made during its `openSession` await. To close that gap, have the arbiter re-check `arbitration.decision` after the host's session await, before selecting; for example, add a "select only if the active id is unchanged since the call started" guard to `FanController.apply` when it is called from the arbiter.

### 16. After a relaunch the baseline is captured from the persisted active profile, which may be the one an automation applied

- Severity: medium  ·  `FanControl/Sources/FanControlKit/FanProfileArbiter.swift:102`  ·  slice: arbiter-power-workload
- Scenario: The user's profile is Quiet. On battery a rule applies Automatic, and the store persists Automatic as active. The app relaunches on battery, and the first claim sets baselineProfileID to Automatic. When the user plugs in, the rule ends and the arbiter 'returns' to Automatic instead of Quiet. ProfileArbitration is not persisted, so the user's own profile is lost. The same applies to workload claims.
- Verification: I checked the code and the scenario happens as described. `FanProfileArbiter.reconcile` applies the automatic winner through `FanControlManager.applyFanProfile` → `controller.applyProfile` → `ProfileSelectionRollback.select`, which sets `store.activeProfileID = profile.id` (FanController.swift:334). `profileStore` has `didSet { persistProfileStore() }` (FanControlManager.swift:260-261), so a profile chosen by a power or workload rule is saved to UserDefaults as the active profile. `ProfileArbitration` and its `baselineProfileID` are memory-only. On launch, `FanControlPowerProfiles.start()` and `WorkloadProfileCoordinator.start()` run, and nothing withdraws claims or restores the baseline at quit. So after a relaunch, the first `setClaim` (FanProfileArbiter.swift:101-102) sets `baselineProfileID = host.activeFanProfileID`, which is the profile the rule applied. When the rule ends, `decision` falls back to that wrong baseline ("Your profile"), and the user's own choice (for example Quiet) is lost until they pick it again. The same happens with workload claims. If no claim comes on the next launch, the automation's profile simply stays active. Severity: medium. Nothing crashes or makes the SMC unsafe, but fans keep running a profile the user did not choose, and nothing in the app shows it.
- Suggested fix: Save the baseline outside the profile store. In `FanProfileArbiter`, add a `UserDefaults` key (for example `fanControl.arbiter.baselineProfileID`). Write `arbitration.baselineProfileID` to it whenever it changes: on the first capture in `setClaim` and in `activeProfileDidChange` after `noteManualSelection`. In `init(host:)`, read it back, and if `host.fanProfile(id:)` is non-nil, set `arbitration = ProfileArbitration(baselineProfileID: saved)`. Then the `if claim != nil, arbitration.baselineProfileID == nil` capture only runs when nothing was saved. A simpler alternative: in `ProfileStore`, keep a separate persisted `userSelectedProfileID` that only manual picks update, and capture the baseline from that field instead of `activeFanProfileID`.

### 17. Persisted Low Power Mode memory is never restored after a relaunch when no rule asks for a value

- Severity: medium  ·  `FanControl/Sources/FanControlKit/PowerProfileEngine.swift:167`  ·  slice: arbiter-power-workload
- Scenario: 'On Battery → LPM on' sets LPM and persists the memory {restore=false}. The app quits, the Mac is plugged in (or Power Profiles is turned off), and the app relaunches. lowPowerModeTarget starts as nil, and the first evaluation's target is also nil, so `guard target != lowPowerModeTarget` returns early. LPM stays on indefinitely even though the memory was persisted precisely to survive a relaunch.
- Verification: The defect is real. I read PowerProfileEngine.swift. `lowPowerModeTarget` is an in-memory `Bool?` that starts as nil (line 66), while `memory` is reloaded from UserDefaults in init (lines 90-91). The app calls `start()` at launch through `FanControlPowerProfiles.start()`, which runs an evaluation. If no rule matches (on AC power, Power Profiles disabled because `firstMatch` returns nil, or no matching rule), `syncLowPowerMode(target: nil)` hits `guard target != lowPowerModeTarget` (nil == nil, line 167) and returns before the restore branch (lines 185-193). That leaves the persisted memory in place and Low Power Mode on. It is only given back if a rule later sets a value and then stops matching. The only relaunch test (`lowPowerModeMemorySurvivesARelaunch`) relaunches while still on battery, so it never covers this case. Severity: medium. The user's Low Power Mode setting is silently left changed, which is exactly what the persisted memory is meant to prevent.
- Suggested fix: Make the first sync after launch always run. Add `@ObservationIgnored private var hasSyncedLowPowerMode = false`, and in `syncLowPowerMode` replace the guard with:
```swift
guard !hasSyncedLowPowerMode || target != lowPowerModeTarget else { return }
hasSyncedLowPowerMode = true
lowPowerModeTarget = target
```
On the first evaluation with target == nil, the existing restore branch then runs against the persisted memory. It still keeps the user's value if `current != valueSetByEngine`. With target == true and LPM already on, the `current != target` guard still returns without doing anything, so the existing relaunch test keeps passing. Add a test: relaunch with persisted memory, power source .ac, state = true → expect sets == [false] and memory cleared.

### 18. Restore path clears the LPM memory before the helper write, so a failed restore loses the user's value for good

- Severity: medium  ·  `FanControl/Sources/FanControlKit/PowerProfileEngine.swift:187`  ·  slice: arbiter-power-workload
- Scenario: No rule asks for LPM any more. `self.memory = nil` (also persisted) runs before `await setLowPowerMode(restoreValue)`. If the helper is not running, is pinned to another build, or is at an old protocol version, the write throws. LPM stays as the engine set it, and nothing will retry the restore because both the memory and lowPowerModeTarget now say nothing is pending.
- Verification: The claim holds. I checked the code at caf55c0 in FanControl/Sources/FanControlKit/PowerProfileEngine.swift. In syncLowPowerMode(target: nil), line 186 keeps a local copy of `memory`, then line 187 runs `self.memory = nil`. Through didSet/persistMemory that also removes the UserDefaults key. Only after that does line 193 call `await setLowPowerMode(memory.restoreValue)`. setLowPowerMode catches the error and returns false, but the result is ignored, so the remembered value is never put back. lowPowerModeTarget was already set to nil at line 168. Every later evaluation therefore exits early at line 167 (`nil == nil`), and with memory gone there is nothing left to retry from, including after a relaunch, because the persisted key was deleted.

The failure is easy to hit. The helper is not running, or it is pinned to another cdhash after a rebuild (a normal step until install.sh is run again), or it speaks an old protocol version. Any of these makes the write throw. Low Power Mode then stays at what the engine set (for example on) for good. The only sign is lowPowerModeError. stop() and turning Power Profiles off take the same path.

The first-change branch handles this correctly: it drops memory only when nothing was changed. The restore branch does not do the same. Severity: medium. Nothing crashes, but a system setting the user owns stays changed after the app has promised to give it back.

One related point: memory persisted from an earlier run is never restored after a relaunch either. lowPowerModeTarget starts as nil, so the same early exit at line 167 skips it. The fix below covers that case too.
- Suggested fix: Clear the memory only after the write succeeds, and let a nil target retry while memory is still pending:

```swift
private func syncLowPowerMode(target: Bool?) async {
    // Retry a pending restore (failed write, or memory persisted by an earlier run).
    guard target != lowPowerModeTarget || (target == nil && memory != nil) else { return }
    lowPowerModeTarget = target
    ...
    guard let memory else { return }
    if let current, current != memory.valueSetByEngine {
        kitLog.notice("Low Power Mode was changed by the user; not restoring it")
        self.memory = nil
        return
    }
    guard current != memory.restoreValue else { self.memory = nil; return }
    if await setLowPowerMode(memory.restoreValue) {
        self.memory = nil
    }   // on failure keep memory (persisted); the next evaluation/tick retries
}
```

### 19. LPM restore flattens per-power-source settings: the engine reads the current-source state and writes it back with `pmset -a`

- Severity: medium  ·  `FanControl/Sources/FanControlKit/PowerProfileEngine.swift:175`  ·  slice: arbiter-power-workload
- Scenario: The user has LPM set to 'Only on Battery' (b=1, c=0). On AC a rule turns LPM on: restoreValue is the AC value (false) and `-a 1` is written. When the user unplugs, the rule stops matching. ProcessInfo reports true, which matches valueSetByEngine, so `-a 0` is written and battery LPM is now off. The user's 'Only on Battery' setting is silently replaced with 'Never'. The reverse case turns it into 'Always'.
- Verification: Confirmed at caf55c0. `PowerProfileEngine.syncLowPowerMode` (FanControl/Sources/FanControlKit/PowerProfileEngine.swift:166-194) stores a single Bool, `restoreValue = current`, where `current` is `ProcessInfo.isLowPowerModeEnabled`, which is the state for the current power source only. Both setting and restoring then go through the helper, whose argv is fixed to `pmset -a lowpowermode 1|0` (FanControl/Sources/FanControlXPC/LowPowerModeCommand.swift:18-20). `-a` writes both the battery and AC profiles.

The claimed scenario plays out as described. The user has "Only on Battery" (b=1, c=0) and is on AC, so `current` is false. A rule turns LPM on: memory becomes {restoreValue: false, valueSetByEngine: true} and `-a 1` is written. When the rule stops matching (on unplug or any other trigger), `current` is true, which equals `valueSetByEngine`, so the user-change check passes. `current != restoreValue`, so `-a 0` is written and the battery value is now 0. "Only on Battery" has become "Never". The reverse case (b=0, c=1 on battery with a rule forcing on, or b=1, c=0 on battery with a rule forcing off) turns it into "Always".

The restore is even lossy without the unplug: the per-source pair (b, c) is never captured, so any rule that changes LPM and later releases it collapses a split setting into one value. That is wrong behaviour, a silent change to a system power setting. Severity: medium-low. Nothing crashes and nothing touches safety, but the user's System Settings choice is overwritten for good.
- Suggested fix: Remember and restore each power source separately.

1. Extend `LowPowerModeMemory` to `restoreBattery: Bool?` and `restoreAC: Bool?`. Take the values from `pmset -g custom` (readable without root) by parsing `lowpowermode` under the "Battery Power:" and "AC Power:" sections. Do this before the first change, instead of using `ProcessInfo`.
2. Add a helper request `restoreLowPowerMode(battery: Bool, ac: Bool)`. Its argv must stay fixed and allow-listed: `pmset -b lowpowermode 0|1` and `pmset -c lowpowermode 0|1`. Add these to `LowPowerModeCommand`'s allowed invocations and give them the same rate limit and read-back.
3. In `syncLowPowerMode`'s restore branch, call that request with the two remembered values. If the per-source read fails, fall back to today's `-a` behaviour, or better, skip the restore and log it.

A smaller alternative is to set and restore only the current source (`-b` when on battery, `-c` on AC) and remember which source was written. This still needs the extra argv entries in the helper allow-list.

### 20. A slow Low Power Mode request can outlast the client's 8 s timeout and tear down the fan session

- Severity: medium  ·  `FanControl/Sources/FanControlXPC/LowPowerModeCommand.swift:130`  ·  slice: helper-xpc-f1-f2
- Scenario: commandTimeout is 10 s per pmset run, and one request runs up to three of them (read, set, read-back), all under requestLock, so it can take up to about 30 s. HelperClient.callTimeout is 8 s and, when it fires, calls invalidate() on the same connection that holds the fan write session. Example: just after wake, powerd is busy and `pmset -g` takes more than 8 s. The app's setLowPowerMode call times out, the client invalidates the connection, and the helper's invalidationHandler calls SessionRegistry.release(owner:). That runs the full restore, so the active fan profile is dropped (Md=0) until the app reopens a session. Because NSXPC delivers one connection's messages serially, writeKey calls queued behind the pmset call also stall meanwhile. Fix: keep the helper's total time well under callTimeout, or send LPM requests on a connection without the session.
- Verification: I traced the whole path and it works as the claim says, but it only bites when pmset is slow, so this is a low-severity latent bug.

1. `LowPowerModeRequestHandler.handle` (LowPowerModeCommand.swift:130 onward) holds `requestLock` and runs `pmset -g`, then `pmset -a lowpowermode N`, then `pmset -g` again. Each run has `commandTimeout = 10` s, so one request can take about 30 s.
2. On the helper side, `LowPowerModeService.setLowPowerMode` calls it synchronously on the connection's queue. Later messages on that connection, such as `writeKey`, wait behind it.
3. On the app side, `PowerProfileEngine` → `HelperLowPowerModeControl` → `helper.client.setLowPowerMode` uses the manager's own `HelperClient`. That is the same `NSXPCConnection` that owns the fan session.
4. `HelperClient.call` races every reply against `callTimeout`, which defaults to 8 s. On timeout it calls `self?.invalidate()`, which runs `dropConnection()`. That invalidates the connection and sets `sessionOpen = false`.
5. The helper's `invalidationHandler` (HelperListenerDelegate.swift:35) then calls `SessionRegistry.shared.release(owner:)`, which restores the fans to SMC automatic control.

So if a pmset call stalls (for example powerd busy right after wake) and pushes the total past 8 s, the active fan profile is dropped silently. The pmset timeout (10 s) is already longer than the client timeout (8 s), so even one hung command triggers it. Normally pmset finishes in milliseconds.
- Suggested fix: Keep the helper's worst case under the client timeout. In `LowPowerModeRequestHandler`, set `commandTimeout` to 2 s and skip the read-back once more than about 6 s have passed since the request started (reply `.ok` with "not confirmed"). Alternatively, give `HelperClient.setLowPowerMode` a longer timeout of its own, e.g. a `call(timeout: 35)` overload. The cleanest fix is to send Low Power Mode requests on a separate short-lived `HelperClient`/connection that holds no session, so a timeout there never invalidates the fan session connection or blocks its message queue.

### 21. The helper can only write `pmset -a`, so restoring Low Power Mode overwrites the user's per-power-source setting

- Severity: medium  ·  `FanControl/Sources/FanControlXPC/LowPowerModeCommand.swift:18`  ·  slice: helper-xpc-f1-f2
- Scenario: The user has Low Power Mode set to 'Only on battery' (`pmset -b lowpowermode 1`) and is on battery. A power rule turns LPM on or off, and PowerProfileEngine remembers the restoreValue as the current boolean (true). On restore the helper runs `pmset -a lowpowermode 1`, so LPM is now 'Always', including on AC. The original per-source configuration (separate -b and -c values) is never read or restored. The read-back parser only looks at the 'Currently in use' value, so it cannot detect this either.
- Verification: This is real, low severity, and already documented. The helper's allow-list contains only `-a lowpowermode 0|1` and `-g` (LowPowerModeCommand.swift:18-28), so every write sets the value for all power sources. `PowerProfileEngine.syncLowPowerMode` (PowerProfileEngine.swift:166-193) stores one Bool as `restoreValue`, taken from `ProcessInfo.isLowPowerModeEnabled`, which is the state in use right now. It restores that Bool through the same `-a` path. Concrete case: the user has "Only on Battery" (-b 1, -c 0) and is on battery. A rule turns LPM off, and `restoreValue` is true. When the rule ends, the helper runs `pmset -a lowpowermode 1`, which leaves -c at 1, so LPM is now "Always" and stays on when the Mac is plugged in. The "given back" value never matches the user's original setting. The read-back parser checks only the "Currently in use" value, so it reports success. helper.md:454-456 says this outright ("A per-source choice … is replaced by the plain value; giving the value back writes the plain value too"). So it is a known limitation, not an oversight. It still breaks the engine's promise to restore the user's setting, and the change to a system setting is permanent, so a maintainer would plausibly fix it.
- Suggested fix: Remember and restore the setting for each power source. In `LowPowerModeCommand`, allow-list `-b lowpowermode 0|1` and `-c lowpowermode 0|1` (fixed argv, still Bool-only), and add a parser for the "Battery Power:" and "AC Power:" sections of `pmset -g custom`, plus that invocation. Change the XPC request to `setLowPowerMode(battery: Bool?, ac: Bool?)`, or add a separate restore request. In `PowerProfileEngine`, capture both values into `LowPowerModeMemory` before the first change (via the helper, or by running `pmset -g custom` without root), and restore each with its own `-b` / `-c` write. A smaller fix: when the per-source values differ, refuse to change LPM (or show a warning) instead of overwriting them with `-a`.

### 22. The close loop toggles the Sound item based on an AXWindows count that lags behind, so it can reopen the menu it just closed

- Severity: low  ·  `DynamicNotchApp/Sources/AirPodsControlCenterDriver.swift:94`  ·  slice: hud-airpods-f5-f7
- Scenario: The first close press is accepted, but Control Center still lists the closing window in AXWindows during its roughly 0.3 s fade. After 0.25 s the loop sees count > baseline and presses again, which reopens the menu. With up to 5 alternating presses, the final state depends on timing, so the menu can be left open and the 'menu always closed' guarantee is broken. A press should be followed by a wait until the window is actually gone (or the press confirmed ignored) before pressing again.
- Verification: I read `close` at AirPodsControlCenterDriver.swift:91-99. It sleeps 0.15 s, then loops up to 5 times: if `windows(of: cc).count > baseline`, it presses the Sound item and sleeps a fixed 0.25 s. Pressing the Sound item toggles the menu (it is the same press that opened it at line 40). The loop never checks whether the last press was accepted; its only signal is the window count. If a close press is accepted but the menu window is still listed in AXWindows when the count is next checked, the loop presses again and reopens the menu. Then it alternates, and whether the menu ends open or closed depends on timing. A window normally stays on screen while it fades out, and 0.25 s is not clearly longer than that fade plus AX latency. Nobody has checked this on a real device: docs/airpods.md "To verify" item 3 still lists "watching that the menu closes every time". So the defect is plausible but its timing is unconfirmed. Severity: low-medium. The cost is that the Sound menu is left open (a UX problem, no safety risk).
- Suggested fix: After each close press, wait for that press to take effect before deciding to press again. Replace the loop body with: `_ = Self.press(item); attempts += 1; if waitFor(timeout: 0.7, { Self.windows(of: cc).count <= baseline ? true : nil }) != nil { return }`. Only re-press after the whole 0.7 s window passes with the menu still listed, i.e. the press was ignored during the open animation. Better still, try `AXUIElementPerformAction(window, kAXCancelAction)` on the menu window first, or send Escape. Neither is a toggle, so retrying them cannot reopen the menu.

### 23. A 'Read Current Mode' issued during the rate-limit wait replaces the in-flight set request, so the user's mode switch is dropped silently

- Severity: low  ·  `DynamicNotchApp/Sources/AirPodsNoiseControl.swift:431`  ·  slice: hud-airpods-f5-f7
- Scenario: drain() removes the job from `queued` (line 427) and then sleeps up to minimumInterval. During that sleep, refresh() passes its `queued[uid] == nil` guard and queues `.read`. After the sleep, `queued.removeValue(forKey: uid) ?? job` picks the read instead of the set. The mode is never pressed, and apply() clears pendingMode because nothing is still pending, so the UI goes back to the old mode. The row's context menu 'Read Current Mode' is not disabled while busy, so this is reachable. A queued read must not override a set.
- Verification: I confirmed this in the code. In drain() (AirPodsNoiseControl.swift:424-438), the job is removed from `queued` at line 427, before the rate-limit sleep at line 430. While it sleeps, refresh(_:) passes its `guard queued[target.uid] == nil` check at line 392, and enqueue() at line 417 writes the `.read` into `queued`. Line 432 then picks the read with `queued.removeValue(forKey: uid) ?? job`, so the `.set` is thrown away and the mode button is never pressed. In apply(), `stillPending` is false, so line 461 clears pendingMode[uid], and displayedMode falls back to the old knownModes value. The user's switch is lost without any error. The trigger is reachable: the widget row's context menu calls 'Read Current Mode' at AirPodsListeningModeViews.swift:37 without `.disabled(service.isBusy(target))`. Only the settings copy at line 138 has that. The window is up to minimumInterval (1 s) after the previous operation, so it takes a quick mode click followed by a right-click and Read. Severity: low to medium. The user's input is lost, but nothing crashes and nothing unsafe happens.
- Suggested fix: Never let a queued read replace a set. In refresh(_:), also return early when this device is mid-operation: `guard queued[target.uid] == nil, busyUID != target.uid else { return }`. Or harden enqueue() so a read never overwrites a waiting set: `if case .read = request, let existing = queued[target.uid], case .set = existing.request { return }`. In drain(), keep the original job unless the newcomer is a set: `let replacement = queued.removeValue(forKey: uid); let (target, request) = { if let r = replacement, case .read = r.request, case .set = job.request { return job }; return replacement ?? job }()`. As a UI safeguard, also add `.disabled(service.isBusy(target))` to the context-menu button at AirPodsListeningModeViews.swift:37.

### 24. A failed or early system_profiler lookup is cached as -1 for the whole session, which hides the control for AirPods 4 (ANC) for good

- Severity: low  ·  `DynamicNotchApp/Sources/AirPodsNoiseControl.swift:357`  ·  slice: hud-airpods-f5-f7
- Scenario: AirPods 4 ANC are detected only by product ID, because the name rule needs 'pro' or 'max'. If system_profiler times out, fails, or runs before the newly connected device appears in its JSON, `productIDs[address] = id ?? -1` is stored and lookingUp is cleared. target(for:) never looks the device up again, so detect() returns nil and the listening-mode row never appears until relaunch.
- Verification: This is a real bug, but a minor one. In `target(for:)` (lines 340-347), a lookup only runs when `productIDs[address] == nil`. `lookUpProductID` (lines 350-360) stores `id ?? -1`, so a lookup that returns nil is cached as -1. Three things return nil from `systemProfilerProductID` (lines 468-482): `process.run()` throwing, the 15 s kill, and JSON that is missing or does not parse. Once -1 is stored, the device is never looked up again for the rest of the session. -1 matches no case in `AirPodsModel.detect` (lines 83-98), so detection falls back to the name rule, which only matches "airpods pro" or "airpods max". AirPods 4 (ANC) (0x201B) therefore get no listening-mode row until the app relaunches. The same happens to Pro or Max AirPods the user has renamed. A transient failure is enough to cause this. In practice the "device not in the JSON yet" case is less likely than the claim says: the parser also searches `device_not_connected`, and a device has to be paired before it can become the output, so it is usually listed. A system_profiler failure or timeout still triggers it. Impact is a hidden feature, not a crash or a safety problem.
- Suggested fix: Cache -1 only when the address was looked up properly and genuinely not found or not Apple. Do not cache a failed lookup, and allow a limited retry. For example, change `productIDLookup` to return `Int??` or a small enum: system_profiler failed/timed out → `.failed`, JSON parsed but address absent → `.notFound`. Then in `lookUpProductID` (line 356):

```swift
switch result {
case .found(let id): self.productIDs[address] = id
case .notFound:      self.productIDs[address] = -1
case .failed:        break   // leave nil so the next target(for:) retries
}
self.lookingUp.remove(address)
```

To stop a persistent failure from re-running system_profiler on every view update, add a retry timestamp per address (e.g. `lastLookupFailure[address]`) and skip the lookup if the last failure was under about 30 s ago. A simpler option: clear the -1 entries in `productIDs` when the default output device changes, or when a Bluetooth device connects, so a reconnect retries the lookup.

### 25. Built-in aliases shadow renamed custom profiles

- Severity: low  ·  `DynamicNotchApp/Sources/Automation/AutomationCommand.swift:113`  ·  slice: automation-surface-f4
- Scenario: `FanProfileReference.init` tries `FanProfileChoice(slug:)` first, and that accepts the aliases 'quiet', 'high', 'auto', 'max', 'full', 'boost'. If the user renames Custom 1 to 'Quiet' or 'Max', `dynamicnotch://profile/quiet` applies Constant Quiet (3000 RPM) instead of the user's profile, and nothing indicates the mix-up. The `.name` path (renamed custom slots, as documented) is never reached for these names. Fix: match display names before falling back to aliases.
- Verification: Confirmed in the code. `FanProfileReference.init` (AutomationCommand.swift:113) checks `FanProfileChoice(slug:)` first, and that initializer (lines 90-101) accepts the aliases auto/smc/quiet/high/boost/max/maximum/full. In `LiveAutomationActions.applyFanProfile` (LiveAutomationActions.swift:27-28), a `.builtIn` reference goes straight to `builtInID(choice)` and never compares against `profile.name`. The raw text is also discarded at that point, so a renamed custom slot can't be considered.

Failure scenario: the user renames Custom 1 to "Quiet" and opens `dynamicnotch://profile/quiet`. That applies the built-in Constant Quiet profile (3000 RPM) and reports "Applied Constant Quiet" instead of applying the user's curve. The same happens for names like "High", "Auto" or "Full". The doc comment on `.name` says it exists for renamed custom slots, but that path is never reached for these names. Exact canonical slugs and default names ("custom-1", "Constant Quiet") are not ambiguous, so only the short aliases cause this.

Severity: low. Both outcomes are safe automation commands (no SMC safety issue), but the wrong profile is applied with no warning.
- Suggested fix: Check user-renamed custom names before falling back to the short aliases. Minimal version: make the alias match only the canonical slug or the default name, and keep a separate alias table that is used only after a name match fails. For example, in `FanProfileReference.init`, return `.name(trimmed)` whenever the normalized text is a short alias (quiet/high/auto/smc/full/maximum). Then in `applyFanProfile`, handle `.name`: first `reference.match(in:)` over the profile names; if nothing matches and `FanProfileChoice(slug: name)` is non-nil, use `builtInID(choice)`. A second option is to carry the raw text in `.builtIn(choice, raw:)`. In `applyFanProfile`, first look for a custom1/custom2 profile whose `profile.name` folds equal to the raw text, and only then use `builtInID(choice)`.

### 26. widget/<id>/show ignores the new widget pages

- Severity: low  ·  `DynamicNotchApp/Sources/Automation/CommandRouter.swift:94`  ·  slice: automation-surface-f4
- Scenario: Since feature/widget-pages, the Nook shows one page of `widgetPages` at a time. `widgetShow` only checks `nookWidgets.contains(widget)` and calls `openNotch()`, without setting the pager's `currentPage` to the page that holds the widget. With the Fan Control widget on page 2 and page 1 showing, `dynamicnotch://widget/fan/show` opens page 1 and still reports 'Showing Fan Control'.
- Verification: The claim holds. `.widgetShow` in CommandRouter.swift:94-97 only checks `actions.nookWidgets.contains(widget)`, which is the flat `SettingsStore[.nookSettings].widgets` list, and then calls `openNotch()`. `LiveAutomationActions.openNotch()` (line 85) only calls `DynamicNotchState.shared.select(.nook)`. Nothing changes the page: `NookWidgetPager.shared.currentPage` is set only by swipes, keys, page dots, drag flips and debug hooks (`show(page:)`), and is never set when the notch opens. The open notch shows `visibleWidgets(settings)`, which is `pages[currentPage]`. So if the widget is on page 2 and the pager is on page 1 (it is persistent shared state), `dynamicnotch://widget/fan/show` opens page 1 and still reports "Showing Fan Control". This is wrong behaviour with a misleading success message. Severity: low/medium (UX, not safety).
- Suggested fix: Add `func showWidget(_ widget: NookWidget)` to the actions protocol and implement it in LiveAutomationActions (on the main actor): `let pager = NookWidgetPager.shared; let pages = pager.pages(SettingsStore[.nookSettings]); if let p = pages.firstIndex(where: { $0.contains(widget) }) { pager.show(page: p, count: pages.count, animated: false) }; openNotch()`. Then call `actions.showWidget(widget)` in place of `actions.openNotch()` in the `.widgetShow` case in CommandRouter.swift.

### 27. widgetShow (URL scheme / dnctl / App Intent) opens the notch but never switches to the page that holds the widget

- Severity: low  ·  `DynamicNotchApp/Sources/Automation/CommandRouter.swift:94`  ·  slice: pages-registry-f9
- Scenario: Displays is on page 2 and NookWidgetPager.shared.currentPage is 0. Running `dnctl widget displays` or the URL `…/widget/displays` passes the nookWidgets.contains check, calls actions.openNotch(), and returns "Showing Displays". The notch opens on page 1, so Displays is not shown. It should call NookWidgetPager.shared.show(page: location(of: widget).page, …).
- Verification: Confirmed, low–medium severity: the command does the wrong thing but nothing crashes. In CommandRouter.swift:94-97, `.widgetShow` checks `actions.nookWidgets.contains(widget)`. That list is the flat `NookSettings.widgets`, so it covers every page. The command then calls only `actions.openNotch()`, and LiveAutomationActions.openNotch() just runs `DynamicNotchState.shared.select(.nook)`. Nothing on this path touches `NookWidgetPager.shared.currentPage`. The open notch draws `pager.visibleWidgets(settings)`, which is `pages[clampPage(currentPage)]`. So when the widget sits on a page other than the current one, the notch opens on the wrong page and the command still reports "Showing <widget>". The only callers of `pager.show(page:count:)` are the swipe/arrow-key/page-dot handlers and DebugHooks, so nothing else moves to the right page either.
- Suggested fix: Add a `showWidget(_:)` method (or a page-select step) to the actions protocol and have the `.widgetShow` case call it instead of `openNotch()`. In LiveAutomationActions:
```swift
func showWidget(_ widget: NookWidget) {
    let pager = NookWidgetPager.shared
    let pages = pager.pages(SettingsStore[.nookSettings])
    if let loc = NookPagesModel.location(of: widget, in: pages) {
        pager.show(page: loc.page, count: pages.count, animated: false)
    }
    openNotch()
}
```
In CommandRouter, the case becomes `guard ...contains(widget) else {...}; actions.showWidget(widget); return .success("Showing \(widget.name)")`. Add `showWidget` to the test fake.

### 28. Deselecting every calendar shows all calendars

- Severity: low  ·  `DynamicNotchApp/Sources/CalendarManager.swift:234`  ·  slice: refactor-crosscut
- Scenario: In Settings ▸ Calendar the user turns off the last selected calendar. `updateSelectedCalendars([])` saves `savedIdentifiers = []`, and `calendarsForQuery` treats an empty selection as `nil`, which EventKit reads as all calendars. The widget and the calendar live activity then show events from every calendar. When the pane reopens, `loadCalendars` ("empty → allCalendars") and `loadSelectedCalendars` ("saved empty → all") turn every toggle back on. `selectionWasExplicit` exists in the settings struct but is never used.
- Verification: I read the code and the claim holds. In CalendarWidgetSettingsView, turning off the last calendar's toggle goes through setSelection([]) and then updateSelectedCalendars([]). That sets selectedCalendars = [] and saves savedIdentifiers = []. In CalendarManager.swift:234, calendarsForQuery maps an empty selection to nil. The fetches at lines 153, 196 and 215 pass that nil to EventKit, which treats nil as every calendar, so the widget and the live activity show events from all calendars. The state does not survive a restart either. loadSelectedCalendars (line 114) has `guard let saved, !saved.isEmpty else { selectedCalendars = allCalendars }`, and the settings pane's loadCalendars (line 67) does `manager.selectedCalendars.isEmpty ? allCalendars : ...`, so every toggle turns back on. A related case: if every saved calendar is deleted, the filter at line 118 gives [], which also falls back to all. CalendarSelectionSettings.selectionWasExplicit is declared but never read or written. The result is the opposite of what the user chose. The code came in with the refactor commits 93b60a7 and 72807e3, inside the cross-cutting range. Severity: low. It is wrong behaviour that the user can see and that persists, but it is not a crash and not a safety issue.
- Suggested fix: Treat `savedIdentifiers == nil` as "never chosen, show all" and an empty array as "show none". In CalendarManager: (1) In loadSelectedCalendars, change the guard to `guard let saved = settings.savedIdentifiers else { selectedCalendars = allCalendars; return }`, so a saved [] stays []. (2) Add `private var selectionIsExplicitlyEmpty: Bool { selectedCalendars.isEmpty && UserDefaults.standard.calendarWidgetSettings.savedIdentifiers != nil }`. Each fetch path (today's events around line 150, the week fetch around 196, the live-activity request around 215) should return an empty result early when it is true, instead of passing nil to the predicate. This is better than relying on what EventKit does with `calendars: []`. (3) In CalendarWidgetSettingsView.loadCalendars, use `let selected = UserDefaults.standard.calendarWidgetSettings.savedIdentifiers == nil ? allCalendars : manager.selectedCalendars`. Instead of the nil-vs-empty test, you could set and read the existing `selectionWasExplicit` flag: set it to true in updateSelectedCalendars and check it in the same three places.

### 29. Calendar widget only reloads when the count of today's events changes

- Severity: low  ·  `DynamicNotchApp/Sources/CalendarWidgetView.swift:64`  ·  slice: refactor-crosscut
- Scenario: `storeChanged` invalidates the per-week cache, but the widget's day list lives in @State and is rebuilt only when `_selectedDate`, `authorizationStatus` or `manager.events.count` change. If an event is edited (time or title), or an event on a non-today day is added or deleted while that day is selected, today's count does not change. The open widget keeps showing the old list or dots until the selected day changes or the view reappears.
- Verification: Confirmed. In CalendarWidgetView.swift:59-64 the widget calls reload() only in onAppear and on changes to `_selectedDate`, `manager.events.count` and `manager.authorizationStatus`. CalendarManager.storeChanged() (line 178) clears the per-week cache and refetches today's events 300 ms later, but nothing observable tells the widget to rebuild its @State `events` / `eventDays`. `events` is replaced only when the filtered list differs, and the widget watches only its count. So several cases leave the open widget showing stale rows or dots until the selected day changes or the view reappears: an edit to an event's title or time, a same-count swap (one event deleted and another added), or any add or delete on a day other than today (strip dots or the selected non-today day). A second problem makes this worse: even when reload() does run, line 262 replaces `events` only if the list of calendarItemIdentifiers changed, so an edit that keeps the same events never reaches the UI. Severity: low. The data is stale but nothing breaks, and it fixes itself when the day changes or the view reappears.
- Suggested fix: In CalendarManager, add an observed `private(set) var revision = 0`. Increment it at the end of the coalesced refresh that storeChanged schedules, after `reloadEvents()` in scheduleRefresh. Incrementing on every invalidateDayCache call would reload the widget once for each notification in a sync burst. Also increment it in the NSCalendarDayChanged handler and when the selected calendars change. In CalendarWidgetView, replace `.onChange(of: manager.events.count)` with `.onChange(of: manager.revision) { _, _ in reload() }`. In reload(), assign `events = list` without the identifier check, or compare `(calendarItemIdentifier, lastModifiedDate, startDate, endDate, title)` instead, so that edits show up.

### 30. The read hold-off is measured from when the write was enqueued, so a slow refresh overwrites the slider with values read before the write

- Severity: low  ·  `DynamicNotchApp/Sources/DisplayControlService.swift:422`  ·  slice: displays-downloads-usage-f6-f8-f10
- Scenario: limiter.flush records lastSend on the main actor when the write is dispatched, but the write is queued on the serial ioQueue behind a refresh that is already running. That refresh read the old VCP values. If it takes longer than readHoldOff (1.5 s), finishRefresh sees isHeld == false and replaces the new brightness/contrast with the stale reading, and the slider snaps back until the next refresh 15–300 s later. A refresh takes that long with two monitors × 4 VCP codes with 50 ms delays and retries, or on a first capabilities read of up to 64 fragments. Fix: hold-off from write completion, or a per-key write generation.
- Verification: I confirmed this by reading the code. `refresh()` (line 372) does every DDC/built-in read inside a single `ioQueue.async` block, using values captured when the refresh starts. `flush(_:)` (line 552) calls `limiter.flush(key:now: Date())`, which sets `lastSent` on the main actor when the write is enqueued. The write then waits on the serial `ioQueue` behind any refresh already running. `finishRefresh` (line 422) keeps the old slider value only when `isHeld(key)` is true. `isHeld` is true only if a write is pending/scheduled or `Date() - lastSend < readHoldOff` (1.5 s, line 466). Nothing ties the hold to the refresh having started before the write. So if a refresh is reading when the user moves a slider, and it finishes more than 1.5 s after the flush, `states` gets the brightness/contrast/volume read before the write. The slider snaps back. The hardware does get the new value, so the next refresh corrects it, and the slider stays wrong until then. A refresh that runs over 1.5 s is plausible. The first `readCapabilities()` (uncached, multi-fragment) plus up to 4 `readVCP` calls per external display, across several displays, can easily take seconds. Severity: low–medium. It is a visible UI glitch that lasts until the next refresh, the display ends up at the requested value, and there is no crash or wrong hardware state.
- Suggested fix: Make the hold-off relative to the refresh. Add `@ObservationIgnored private var refreshStartedAt = Date.distantPast` and set `refreshStartedAt = Date()` in `refresh()` right after `readInFlight = true`. In `finishRefresh`, check `isHeld(key) || (limiter.lastSend(key).map { $0 >= refreshStartedAt } ?? false)` instead of `isHeld(key)` alone, so any write flushed after this read began keeps the slider value. An alternative is a per-key write generation counter that `refresh()` captures and `finishRefresh` compares.

### 31. A failed or vcp-less capabilities read is never cached, so it is repeated on every refresh and blocks the I/O queue

- Severity: low  ·  `DynamicNotchApp/Sources/DisplayControlService.swift:494`  ·  slice: displays-downloads-usage-f6-f8-f10
- Scenario: Capabilities are cached only when readCapabilities returns a parsed DDCCapabilities. A monitor whose capabilities string has no vcp( group, or which never sends an empty terminating fragment, is read again on every refresh: up to 64 fragments × (write + 50 ms + read) and retries, several seconds each time. The serial ioQueue is busy for that whole time, so slider writes to every display queue up behind it, and the stale-read finding above becomes more likely.
- Verification: This one is real, with low-to-medium severity. In DisplayControlService.swift:493-497, `learned[d.key]` is set only when `channel.readCapabilities()` returns a non-nil `DDCCapabilities`. Two cases get no entry at all. First, a read that throws. Second, a read that finishes but returns nil because `DDCCapabilities(parsing:)` (DDCPacket.swift:206) finds no `vcp(` group. Nothing records that the read was already tried, so `capabilitiesCache[d.key]` stays nil. Every `refresh()` then calls `readCapabilities` again; refresh runs on the DDC timer at least every 5 s, on screen changes and on follow-up refreshes. A vcp-less string, or a monitor that never sends the empty end fragment, can take up to 64 fragments. Each fragment is a write, 50 ms, then a read, with up to 3 attempts and a 30 ms gap between retries (DDCTransport.swift:79-105), so that is several seconds per refresh. A monitor that rejects the request outright still costs about 0.25 s per refresh. All of this runs on the serial `ioQueue`, so DDC slider writes to every display, and the built-in brightness reads, wait behind it on every cycle. The hardware is being probed again for an answer that will not change while the channel stays the same.
- Suggested fix: Remember that the read was tried, not only that it succeeded. Add a cache of tried display keys next to `capabilitiesCache`, e.g. `@ObservationIgnored private var capabilitiesTried: Set<String> = []`. Pass `tried = capabilitiesTried` into the ioQueue closure and give `read` an `inout attempted: Set<String>` parameter. Then change line 494 to:
```swift
if caps == nil, !tried.contains(d.key) {
    attempted.insert(d.key)
    if let c = try? channel.readCapabilities() { caps = c; learned[d.key] = c }
}
```
In `finishRefresh`, add the new keys with `capabilitiesTried.formUnion(attempted)`. Clear `capabilitiesTried`, or remove the display's key, when channels are rebuilt (`rebuildChannels` / `channelsStale`) or the display list changes, so a display that is plugged in again gets probed again. A simpler alternative: store the failure time and retry no more than every few minutes.

### 32. The channel map is rebuilt on every refresh while any external display has no DDC endpoint

- Severity: low  ·  `DynamicNotchApp/Sources/DisplayControlService.swift:388`  ·  slice: displays-downloads-usage-f6-f8-f10
- Scenario: rebuildChannels compares the channel keys with all external display IDs. A display that never gets a channel (Sidecar/AirPlay/DisplayLink, or an unmatched port) makes the sets differ forever. So every refresh re-enumerates the IORegistry and creates new IOAVService objects for all monitors, discarding the working channels, instead of rebuilding only on screen changes or wake.
- Verification: This one is real, but it is low severity. It costs efficiency and nothing breaks. At DisplayControlService.swift:388, `rebuildChannels` is true whenever `Set(channels.keys) != Set(external display IDs)`. `SystemDisplayHardware.ddcChannels` (DisplayHardware.swift:85-97) only adds an entry when `DisplayMatcher` matches the display to an endpoint and `IOAVServiceDDCTransport(proxy:)` succeeds. A Sidecar, AirPlay or DisplayLink screen, or any display that doesn't match, therefore never gets a key, so the sets never become equal. The same thing happens when `ddcEnabled` is false and an external display is attached: the channels come back as `[:]` every time, though the rebuild is cheap in that case. As a result, every timer tick (every `max(refreshInterval, 5)` seconds) and every refresh after a write calls `DDCServiceLocator.endpoints()` again, which enumerates the IORegistry. It also creates a new IOAVService for every matched monitor and throws away the working `DDCChannel`s. Channels are already rebuilt correctly on screen-parameter changes and on wake through `channelsStale` (lines 273 and 325). Readings stay correct, so the impact is wasted IOKit work, plus any per-channel `timing` state being reset on each poll.
- Suggested fix: Track the display list the channels were built for instead of the keys that came back. Add `@ObservationIgnored private var channelDisplayIDs: Set<CGDirectDisplayID> = []`. In `refresh()`, compute `let externalIDs = Set(list.filter { !$0.isBuiltIn }.map(\.id))` and set `let rebuildChannels = channelsStale || externalIDs != channelDisplayIDs`. When `rebuildChannels` is true, set `channelDisplayIDs = externalIDs` (either right there or in `finishRefresh`). Also set `channelsStale = true` whenever `settings.ddcEnabled` changes, so turning DDC on still builds the channels.

### 33. 1 s polling during downloads re-sums large directories every tick and can keep running indefinitely

- Severity: low  ·  `DynamicNotchApp/Sources/DownloadsWatcher.swift:387`  ·  slice: displays-downloads-usage-f6-f8-f10
- Scenario: While a download is active, or while `published` is non-empty, updatePolling rescans every second. Each scan calls directorySize (an enumerator of up to 20,000 entries) on every top-level directory among the listed items. With an unpacked SDK or project folder in Downloads, that is tens of thousands of stat calls per second for the whole download. Also, any publisher that never unpublishes (for example its process dies) leaves an entry in `published`, so the 1 s rescans continue for as long as the widget is in the Nook.
- Verification: Confirmed from the code. `updatePolling()` (line ~387) sets a 1 s repeating timer whenever `hasActiveDownloads || !published.isEmpty`. Each tick calls `scan()`, and that runs `read(...)`. For every top item that is a non-partial directory (up to `itemCount`, which can be 10), `read` calls `directorySize`, an unbounded `FileManager.enumerator` walk of up to 20,000 entries with a resourceValues lookup on each. Directory sizes are not cached and do not change during the download, yet they are re-summed every second. Example: during a long download with an unpacked SDK or a node_modules-style folder among the 5–10 newest items, that is tens to hundreds of thousands of stat calls per second, for the whole download, on the utility queue. It wastes CPU, battery and disk I/O, and on a network folder it can make each scan take longer than 1 s, so scans pile up back to back through `scanAgain`. This is a real performance defect, not style. Severity: low–medium. It is not a crash or a correctness bug, but the load is sustained while any download is running. The second half of the claim is speculative: that a publisher which dies leaves `published` non-empty forever. Foundation's file-progress subscription normally calls the unpublishing handler when the publishing connection goes away. I could not prove it leaks, so I am not counting that part.
- Suggested fix: Stop re-summing directories on the poll path. In `read(folder:...)`, take a `knownSizes: [String: (modified: Date, size: Int64?)]` cache. It is passed in from the main actor, or kept as a static dictionary used only on scanQueue. Call `directorySize` only when the directory's `contentModificationDate` (or `added`) differs from the cached entry, and otherwise reuse the cached size. Simpler alternative: add a `sumDirectories: Bool` parameter to `read`. Pass false for scans fired by the 1 s/15 s pollTimer and true for scans fired by the vnode source, install or settings changes. Carry the previous `items[i].size` forward for directories that have the same id and modified date. As an optional safeguard, also require the polling branch to have at least one `progress` entry that is not stalled. Polling then stops once `published` holds only progress entries that match no listed item.

### 34. Without Input Monitoring, the fallback key source is only a global monitor, which never receives events while DynamicNotch is the active app

- Severity: low  ·  `DynamicNotchApp/Sources/HUDMonitor.swift:265`  ·  slice: hud-airpods-f5-f7
- Scenario: `NSEvent.addGlobalMonitorForEvents` does not get events delivered to the app itself. With Input Monitoring off, when DynamicNotch is frontmost (for example the Settings ▸ HUD pane is open and the user presses brightness keys to test it), the media-key NX_SYSDEFINED events go to the app's own event queue. No brightness or keyboard HUD appears, and the diagnostics keep saying 'Global event monitor (no key seen yet)'. A matching addLocalMonitorForEvents(.systemDefined) is missing.
- Verification: Confirmed. Without Input Monitoring, `startGlobalMonitor()` (HUDMonitor.swift:264-268) registers only `NSEvent.addGlobalMonitorForEvents(matching: .systemDefined)`, and nothing else in the app registers a local `.systemDefined` monitor (grep shows local monitors only for scroll, keyDown and mouse). AppKit global monitors never receive events posted to the app's own event queue. So while DynamicNotch is the active app (for example with the Settings window focused), brightness and keyboard-backlight NX_SYSDEFINED key presses are missed. In that case no HUD appears and `mediaKeyEventsSeen` stays at 0, so the diagnostics keep saying "no key seen yet". docs/hud.md does not mention this limitation. Volume is less affected because the CoreAudio listeners still catch volume changes. The event tap path (with Input Monitoring) is fine. Severity: low. It is a functional gap in a cosmetic HUD and only happens while the app is frontmost, but that is exactly when the user is testing it from the HUD settings pane.
- Suggested fix: In `startGlobalMonitor()`, also add a local monitor that passes events through, and remove both in `stop`:
```swift
@ObservationIgnored private var localMonitor: Any?
...
localMonitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { event in
    MainActor.assumeIsolated { HUDMonitor.shared.handleSystemDefined(event) }
    return event
}
...
if let localMonitor { NSEvent.removeMonitor(localMonitor) }
localMonitor = nil
```
Also update the condition at line 179 so that a missing local monitor triggers a restart, not just a missing `globalMonitor`.

### 35. start() calls refreshPermissions() before the volume.onChange callback is installed, so the volume baseline is never seeded when Input Monitoring is already granted

- Severity: low  ·  `DynamicNotchApp/Sources/HUDMonitor.swift:118`  ·  slice: hud-airpods-f5-f7
- Scenario: With Input Monitoring granted at launch, refreshPermissions() sees a change (false→granted) while `started` is already true and calls reconfigure(). That starts the volume observer, and its start() calls onChange, which is still nil. lastLevels[.volume] stays nil and the later reconfigure() skips volume.start(). The first CoreAudio notification after the quiet window that does not actually change the level (a mute or scalar re-notify, or another app writing the same volume) then counts as levelMoved (nil vs value) and shows a spurious volume HUD.
- Verification: I checked this against the code and the ordering bug is real, but its effect is small. In HUDMonitor.start(), `started = true` is set at line 113 and refreshPermissions() runs at line 118. `volume.onChange` is not installed until line 120. If Input Monitoring is already granted, refreshPermissions() sees inputMonitoringGranted go false→true. Because `started` is already true, it calls reconfigure(). With volume enabled, reconfigure() calls volume.start() (line 168). That call takes its baseline reading and calls `onChange?(level, muted, true)` (line 474) while onChange is still nil, so lastLevels[.volume] is never seeded. Only volume.lastMuted gets set, directly at line 473. The second reconfigure() at line 156 then skips volume.start() because isRunning is already true. Nothing seeds lastLevels[.volume] until the first CoreAudio notification or a volume key press. The first value notification after the quiet window therefore hits the `(l?, nil)` case at line 358 and sets levelMoved = true. If that notification carries no actual level or mute change, a spurious volume HUD appears. Examples are a per-channel scalar re-notify, which bind() subscribes to on purpose, or another app writing the same volume. If the first change is a real decrease, the direction is computed against 0 and reported as .up. The cause is a plain init-order mistake. It is low severity: a cosmetic HUD flash or wrong direction once per launch, only when Input Monitoring is already granted.
- Suggested fix: In HUDMonitor.start(), install the callbacks before anything can start the observer: move the `volume.onChange = { ... }` and `levelRead.onResult = { ... }` assignments above `refreshPermissions()`. Alternatively, set `started = true` only after the callbacks are installed, or call refreshPermissions() just before the final reconfigure(). Then volume.start() always delivers its baseline reading to volumeChanged and seeds lastLevels[.volume].

### 36. Pages are identified by index and widgets by identity within a page only, so moving a widget across pages destroys and recreates its view during the drag

- Severity: low  ·  `DynamicNotchApp/Sources/Support/NookWidgetGrid.swift:183`  ·  slice: pages-registry-f9
- Scenario: While the user drags the Calculator or Camera widget, an edge-dwell flip moves it from page 0's ForEach to page 1's. SwiftUI tears down the old view and creates a new one: onDisappear stops the camera, and @State is lost (the calculator's typed expression, a widget's scroll position). Going from one page to several (the Group's branch switch) also recreates every widget.
- Verification: This is real, but low severity. Each page builds its own `row()` HStack with its own `ForEach(..., id: \.element)` (NookWidgetGrid.swift:183 and :226). That means a widget's identity is its page's structural position plus the widget value. During a drag, the edge-dwell `flipPage()` (NookWidgetPager.swift:472) runs `NookPagesModel.move(widget, toPage: target, …)` on `pager.draftPages`. `pages()` returns that draft directly, so the widget leaves page p's ForEach and joins page p±1's. SwiftUI treats this as removal plus insertion, not a move.

The consequences match the claim:
- `CalculatorWidgetView` loses its `@State input`, `copiedID` and `focusSession`.
- `MirrorWidgetView`'s `onDisappear` sets the mode to inactive and calls `stopCamera()`. A live mirror drops its session in the middle of the drag and only restarts if `autoOpen` is set.
- The `body` Group's branch switch from `page(0, …)` to `pageStrip` (and back) also recreates every widget. That happens when the page count goes from 1 to more than 1, for example after a settings change or when a committed drag prunes a page. The drag itself stays consistent, because drag state is keyed by the `NookWidget` value, so this is only lost state. There is no crash.
- Suggested fix: Keep each widget's view identity independent of its page. The simplest fix: render every page's cells inside one shared container, with a single `ForEach(allWidgetsFlattened, id: \.self)`. Place each cell at `geo.frame(of: widget)` with `.position`/`.offset` instead of nesting a ForEach per page. Always use the pageStrip path, so the `pages.count == 1` branch is never a different subtree; a single page is just a strip of one. This also removes the Group branch switch. If you keep the per-page ScrollViews, the cheaper fix is to move a widget's transient state out of the view. Keep the Calculator's `input`/`copiedID` in `CalculatorHistoryStore.shared` or a small shared model, and keep the Mirror's session in `CameraManager.shared`. Also defer `stopCamera()` in `MirrorWidgetView.onDisappear` while `NookWidgetPager.shared.dragged == .mirror`.

### 37. edgeSide is never reset when a drag ends or is cancelled, so the edge-dwell page flip stops working on the next drag

- Severity: low  ·  `DynamicNotchApp/Sources/Support/NookWidgetPager.swift:406`  ·  slice: pages-registry-f9
- Scenario: The user drags a widget to the right edge zone (edgeSide = 1) and drops it there. mouseUp invalidates edgeTimer but leaves edgeSide = 1. On the next drag, moving into the same right edge zone gives side == edgeSide, so updateEdgeDwell returns early without arming a timer. The widget can't be carried to the next page until the pointer leaves the zone and comes back. The same applies after an Escape cancel and after uninstall.
- Verification: Confirmed, low severity. `edgeSide` is only assigned in updateEdgeDwell (lines 463–464). mouseUp (line 406), the Escape cancel (line 596) and uninstall (line 304) all invalidate edgeTimer but leave edgeSide at ±1. updateEdgeDwell runs `guard side != edgeSide else { return }` before it arms a timer. On the next drag, if the first drag event already falls in the same 28 pt edge zone (`edgeZone`), side equals the stale edgeSide, so no timer is armed and the page never flips. This happens when you lift a widget near the edge and drag outward, or press-and-hold right at the edge. The page flip only comes back once the pointer leaves the zone, which updates edgeSide to 0, and then re-enters it. The impact is narrower than the claim says: if the first drag event of the next drag lands outside the zone, edgeSide resets to 0 and everything works normally. It is still a real stale-state bug.
- Suggested fix: Reset the dwell state everywhere the timer is torn down. Add a helper `private func stopEdgeDwell() { edgeTimer?.invalidate(); edgeTimer = nil; edgeSide = 0 }` and use it in mouseUp (line 406), the Escape branch of handleKey (line 596), uninstall (line 304) and the early-out in flipPage (line 476). Also call it in lift() right before pager.beginDrag, so every drag starts with edgeSide == 0.

### 38. A claimed swipe whose .ended/.cancelled event never reaches this monitor leaves isSwiping true, so the notch can't close

- Severity: low  ·  `DynamicNotchApp/Sources/Support/NookWidgetPager.swift:512`  ·  slice: pages-registry-f9
- Scenario: The user swipes on the trackpad and the swipe is claimed (pager.isSwiping = true). The strip then slides a Timer wheel column (TimerCreatorView's local scroll monitor, which returns nil while it is hovered) under the stationary pointer. If AppKit runs that monitor first, the remaining .changed/.ended events are consumed, endSwipe never runs, and swipeOffset stays mid-swipe. isInteracting stays true, and the notch stays open until the grid disappears, which it never does because notchIsBusy blocks the close. scrollWheel also returns early when pager.dragged != nil without ending a claimed swipe. Plausible: it depends on the order in which local monitors run.
- Verification: This is real but low severity, and it fixes itself. `pager.isSwiping` is set to true when a swipe is claimed (NookWidgetPager.swift:538). Only `endSwipe` clears it (line 567), and `endSwipe` runs only when the grid monitor sees a `.ended`/`.cancelled` scroll event, or on `uninstall`. `isInteracting` includes `isSwiping` (line 90), and `NotchViewModel.notchIsBusy` returns true while it is set (NotchHover.swift:90). So a lost end event keeps the notch from closing, and `swipeOffset` stays mid-swipe. `uninstall` only runs when the grid is torn down, which needs the notch to close, so it cannot break the loop.

The claimed way to lose the end event holds up in the code. TimerCreatorView adds its own local `.scrollWheel` monitor from `.onHover` (TimerCreatorView.swift:274-276), so it is added after the grid's monitor. While `hovering` is true it returns nil for every scroll event, horizontal ones and `.ended` included (lines 313-323). If AppKit runs that monitor first, the grid never sees the rest of the gesture.

Two things are not verified and make this plausible rather than certain: the order AppKit runs local monitors in (I believe the newest runs first), and whether `onHover` fires when content slides under a pointer that has not moved. Separately, `scrollWheel` returns early when `pager.dragged != nil` (line 512), before the `.ended` branch, so an end event that arrives during a drag never resets a claimed swipe either.

It is not permanent. Any later trackpad gesture over the notch window reaches the `.ended` branch, which calls `endSwipe` without checking the swipe state. But a user who moves the pointer away to close the notch sends no such gesture, so the notch stays open, showing a half-swiped strip, until they come back and scroll.
- Suggested fix: (1) In TimerCreatorView's scroll monitor, consume only the column's own vertical scrolling and let everything else pass, e.g. `guard hovering, !NookWidgetPager.shared.isSwiping, abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) else { return event }`. Always return `.ended`/`.cancelled` phase events (non-empty phase with no deltas) so the pager sees them. (2) In `NookWidgetGrid.scrollWheel`, handle `.ended`/`.cancelled` before the `pager.dragged == nil` guard, e.g. `if s.phase.contains(.ended) || s.phase.contains(.cancelled) { … endSwipe … }`. Also, when a new `.began`/`.mayBegin` arrives while `swipe` is still `.claimed`, call `endSwipe(cancelled: true)` first. (3) Optional backstop: clear `isSwiping` (and settle `swipeOffset` back to 0) if no `.changed` sample arrives for about 0.5 s, e.g. check `lastSwipeTime` in `isInteracting`: `isSwiping && now - lastSwipeTime < 0.5`.

### 39. Workload apply errors are read from arbiter.lastError right after setClaim, which may return before the apply runs; failed claims are never retried

- Severity: low  ·  `DynamicNotchApp/Sources/Support/WorkloadProfileCoordinator.swift:41`  ·  slice: arbiter-power-workload
- Scenario: A power apply is in flight, so setClaim(workload) only sets reconcileAgain and returns. The coordinator reads the previous lastError (nil) and clears state.lastApplyError. When the coalesced Boost apply then fails, the Automation tab never shows the error. sendClaim dedupes identical claims and the arbiter skips a failedDecision, so the workload profile stays unapplied until its rule changes.
- Verification: Confirmed by reading the code. In FanProfileArbiter.swift:159-163, when `isApplying` is true, `reconcile()` only sets `reconcileAgain = true` and returns, so `setClaim(_, for: .workload)` returns before the workload apply has run. The closure in WorkloadProfileCoordinator.swift:41-44 then reads `arbiter.lastError` straight away. At that moment lastError is either nil or left over from the earlier apply, so the closure doesn't throw, and `sendClaim` sets `state.lastApplyError = nil` (line 204).

When the coalesced loop later runs and `applyFanProfile` fails, the arbiter sets `failedDecision` and `lastError` (lines 183-186). Nothing in the coordinator watches for that, and `state.lastApplyError` is the only error the Automation tab shows (FanControlAutomationTabView.swift:33), so the failure is never displayed.

A stale error can also go the other way. If the in-flight apply was the same profile from another layer and it fails, its lastError is still set when the closure checks, and that apply's later success would not clear the message the tab shows.

After a failure, recovery is blocked from both sides:
- `sendClaim` drops identical claims (line 197).
- `reconcile` skips `decision == failedDecision` (line 172).
- Nobody calls `arbiter.retry()`.

So the Boost/workload profile stays unapplied, with no visible error, until the rule's decision changes. The power path does not have this problem because PowerProfileEngine reads `arbiter.lastError` live. Severity: medium. Nothing unsafe happens to the fans (the previous or baseline profile stays active), but the workload automation silently fails to take effect.
- Suggested fix: Report the error from the arbiter's live state instead of a snapshot taken right after setClaim. Two options:

1. In FanControlAutomationTabView, or as a computed property on FanControlAutomationState, show `FanProfileArbiter.shared.lastError` when `arbiter.decision?.layer == .workload`. This is what PowerProfileEngine does at line 223. Drop the post-setClaim check in the closure.

2. Make a coalesced caller wait for the pass that applies its claim. In FanProfileArbiter, keep the running loop as `private var reconcileTask: Task<Void, Never>?`. Have `reconcile()` await that task, then run again if `reconcileAgain` is set. setClaim then returns only after its decision was applied or failed, and the existing lastError check works.

In both cases, also let a failed workload claim be retried. In `evaluate`, under `.engaged`, call `await FanProfileArbiter.shared.retry()` from the claim task when `arbiter.decision?.layer == .workload && arbiter.appliedDecision != arbiter.decision && !arbiter.isApplying`. Rate-limit it, for example to once per minute.

### 40. `updateLiveActivity` checks the filtered set, so a `.tray` request is never withdrawn while tray activities are disabled

- Severity: low  ·  `DynamicNotchApp/Sources/Tray.swift:560`  ·  slice: refactor-crosscut
- Scenario: `isShown` reads `activeLiveActivities`, which is filtered by `isAllowed`, instead of `requestedActivities`. Steps: files are in the tray, so `.tray` is requested. The user turns off the Live Activities master switch, or the Files Tray toggle, and `.tray` is filtered out. The tray is then emptied: `shouldShow` is false and `isShown` is false, so `removeSync` is skipped and the request stays. When the user turns live activities back on, `recompute()` shows the Files Tray activity with a count of 0. It stays until the tray changes again.
- Verification: This is a real defect, low to medium severity (stale UI, no crash). In `Tray.swift:560`, `isShown` reads `manager.activeLiveActivities`. That set is `requestedActivities.filter(isAllowed)` (`ActiveLiveActivitiesManager.recompute`). The `.tray` descriptor's gate is `.liveActivitiesSettings` (`LiveActivityDescriptor.swift:88`), so `isAllowed(.tray)` is false when `liveSettings.enabled` is off or when "tray" is in `disabledActivities`. In that state, emptying the tray gives shouldShow=false and isShown=false, so `removeSync(.tray)` is never called and `.tray` stays in `requestedActivities`. When the user turns the setting back on, the `observe(.liveActivitiesSettings)` handler calls `manager.recompute()`, and the Files Tray activity appears with 0 files. Nothing calls `Tray.updateLiveActivity` on that settings change, so it stays until `files` changes again. The opposite case also misbehaves slightly: adding files while the activity is filtered calls `insertSync` again, but the guard turns that into a no-op.
- Suggested fix: Compare against the request set, not the filtered set. In `Tray.updateLiveActivity`, change the line to `let isShown = manager.requestedActivities.contains(.tray)`. `insertSync`/`removeSync` already guard on `requestedActivities`, so you could also call `shouldShow ? manager.insertSync(.tray) : manager.removeSync(.tray)` without the check.

### 41. The detail pane's Add/Remove from Nook edits `widgets` directly and leaves `widgetPages` out of date

- Severity: low  ·  `DynamicNotchApp/Sources/WidgetsSettingsTabView.swift:110`  ·  slice: pages-registry-f9
- Scenario: Pages = [[a,b],[c]]. In the detail pane the user clicks 'Remove from Nook' for c. Only widgets.removeAll runs, so widgetPages still holds [[a,b],[c]] and the notch shows an empty page 2. Clicking 'Add to Nook' for c then puts it back at its old page position, not on the last page as documented, because the stale entry is still in widgetPages. The list's remove(), in contrast, goes through `pages`.
- Verification: Confirmed, low severity. The bug is real, but the scenario as written is partly wrong. `WidgetsSettingsTabView.remove` (line 110) only runs `nookSettings.widgets.removeAll`, so the removed widget stays in `widgetPages`. `NookPagesModel.pages(stored:flat:)` hides it while it is out of `widgets`. When it is re-added (`widgets.append`, from either the detail pane or the list's add), the stale entry claims it first, so it returns to its old page and position instead of going to the last page. The list's `add` comment documents last-page placement, and its `remove` (NookWidgetPagesSettingsList.swift:129) goes through `pages` precisely to avoid this. Correct failure case: pages [[a,b],[c]]; remove `a` from the detail pane, then add `a` again; `a` comes back at page 1, index 0 instead of at the end of page 2. The example in the claim (removing `c`, the last page's only widget) proves nothing, because its old position is already on the last page. The "empty page 2" part is not specific to this path either: the list's remove also stores [[a,b],[]].
- Suggested fix: In DynamicNotchApp/Sources/WidgetsSettingsTabView.swift, make remove go through `pages` like the list does:
```swift
private func remove(_ widget: NookWidget) {
    nookSettings.pages = nookSettings.pages.map { $0.filter { $0 != widget } }
}
```
Better still, move add/remove into a `NookSettings` extension shared by both views. The dead `widgetList`, whose `.onMove` also edits `widgets` directly, can be deleted.

### 42. dnctl turns a multi-word profile name into a path and the lookup fails

- Severity: low  ·  `DynamicNotchApp/Tools/dnctl/main.swift:74`  ·  slice: automation-surface-f4
- Scenario: The usage text advertises `dnctl profile <…|name|uuid>`, but `dnctl profile My Curve` builds `dynamicnotch://profile/My/Curve`. The parser joins the segments into 'My/Curve' and reports 'No fan profile named My/Curve'. Only a quoted single argument works. Fix: join the words after `profile` with a space.
- Verification: This happens as described, but it is low severity: a usability bug in the CLI, with no impact on safety or the fan helper. In DynamicNotchApp/Tools/dnctl/main.swift (lines 59–76), every word that isn't key=value becomes its own percent-encoded path segment, joined with "/". So `dnctl profile Late Night` builds `dynamicnotch://profile/Late/Night`. On the app side, AutomationCommand.parse (DynamicNotchApp/Sources/Automation/AutomationCommand.swift, lines 210–233) splits the path into segments, and the profile case rejoins them with `rest.joined(separator: "/")`. The lookup is therefore for the name "Late/Night", which fails with profileNotFound ("No fan profile named “Late/Night”"). The default names fail the same way: `dnctl profile Constant Quiet` becomes "Constant/Quiet", because normalize() strips spaces, -, _ and . but not "/". The usage text advertises `profile <…|name|uuid>`, and the tests and docs use names with spaces ("Late Night", "Constant Quiet"). Only quoting the name as one argument (`dnctl profile "Late Night"`), or using a slug, works. The header comment does say "Positional words become the URL path", so this is the generic design, but for the `profile` command it gives the wrong result for the names it advertises.
- Suggested fix: In dnctl/main.swift, after splitting words into `path` and `items`, merge the remaining words for the profile command into one segment, so `"%2F"` encoding is kept for a real slash:

    if let head = path.first, ["profile", "fanprofile"].contains(head.lowercased()), path.count > 2 {
        path = [head, path.dropFirst().joined(separator: " ")]
    }

Optionally, also update the usage line to `profile <…|name (words are joined with spaces)|uuid>`.

### 43. refresh() can overwrite the helper's newer read-back with an older SMC read

- Severity: low  ·  `FanControl/Sources/FanControlKit/ChargeLimitController.swift:140`  ·  slice: helper-xpc-f1-f2
- Scenario: refresh() starts read() and reads CHWA=0. Before that detached read returns, the user turns the limit on: setEnabled runs, the helper writes 1, reading becomes .on, and isBusy is false again. The awaited read then resumes, `guard !isBusy` passes, and reading is set back to .off. The UI shows Off while the SMC holds 1, until the next refresh. The guard only catches a change still in progress, not one that finished while the read was in flight; a generation counter would fix it.
- Verification: The claim holds. In refresh() (ChargeLimitController.swift:138-141), `await read()` gives up the main actor. setEnabled can run from start to finish while the read is in flight: the toggle is reachable through ChargeLimitViews.swift:34/83 while `.task { refresh(ifOlderThan: 30) }` is reading, and any reading older than 30 s triggers a fresh read. setEnabled publishes the helper's read-back and then clears isBusy in its defer. When the stale read resumes, `guard !isBusy` passes, and line 141 overwrites `.on` with the older `.off` (lastRefresh is also bumped, so a refresh within the next 30 s won't fix it). The comment on line 139 says the intent is to keep a change that finished meanwhile, and this guard only catches a change still in progress, so the guard is wrong, not a matter of style. Severity is low: the read is a few-millisecond detached SMC read, while setEnabled needs a prepareHelper plus an XPC round trip, so the window is narrow. The effect is display-only (the UI shows the wrong state until the next refresh), and the SMC state itself is correct.
- Suggested fix: Add a change counter: `@ObservationIgnored private var changeGeneration = 0`. In setEnabled, after `isBusy = true`, do `changeGeneration &+= 1`. In refresh, write `let generation = changeGeneration` before `let value = await read()`, then replace the guard with `guard !isBusy, generation == changeGeneration else { return }`.

### 44. lowPowerModeTarget is recorded before the write, so a failed LPM change is never retried while the rule stays matched

- Severity: low  ·  `FanControl/Sources/FanControlKit/PowerProfileEngine.swift:168`  ·  slice: arbiter-power-workload
- Scenario: A rule asks for LPM on while the helper is briefly unavailable (for example just after a rebuild, before install.sh is re-run), and setLowPowerMode throws. lowPowerModeTarget is already true, so later evaluations (30 s ticks, power or wake notifications) skip at the guard. LPM stays off for as long as the rule keeps matching, even after the helper comes back.
- Verification: The defect is real; I confirmed it by reading the code. In `syncLowPowerMode` (`PowerProfileEngine.swift:167-168`), `lowPowerModeTarget = target` is assigned before the write is attempted. When `setLowPowerMode(target)` fails (it catches the error and returns false), the code only clears `memory` on a first change. It never resets `lowPowerModeTarget`, and nothing else in the file changes it (the only other reference is the declaration at line 66). Every later `apply()` call with the same rule then exits at `guard target != lowPowerModeTarget`. That covers 30 s ticks, context, power and wake notifications, and `requestEvaluation`. So a write that fails while the helper is unavailable (for example after a rebuild, before `install.sh` is re-run) is not retried while that rule stays matched, even after the helper comes back. Low Power Mode stays in the wrong state. The only visible sign is `lowPowerModeError` in the status line, which `setLowPowerMode` sets when the write fails. It recovers only when the matched rule's requested state changes or the engine stops. Severity: medium. The behaviour is wrong but safe: no fan or SMC risk, only power state.
- Suggested fix: In `syncLowPowerMode`, put the failed target back so the next evaluation tries again:

    if await setLowPowerMode(target) {
        memory?.valueSetByEngine = target
    } else {
        lowPowerModeTarget = nil   // retry on the next evaluation
        if isFirstChange { memory = nil }
    }

The alternative is to assign `lowPowerModeTarget = target` only after a successful write, or when `current == target`.

## Rejected claims (not real after verification)

- The Low Power Mode state shown right after a helper write comes from ProcessInfo, which may not have updated yet
- One undecodable app rule drops every app rule, and the next settings edit overwrites the stored list
- Unauthenticated URL fan commands count as manual picks and pause workload/power automation
- dnctl can crash on a non-ASCII command word because of the percentEncodedHost setter
- oldItems' in-progress check misses files that have a published NSProgress or are still being written
- set() still sends DDC writes after DDC/CI is turned off in Settings
- If the on-disk store fails to open, the app silently switches to an in-memory store and recorded usage is lost
- Pager state (isInteracting, currentPage) is one shared object for all screens, so an interaction on one screen keeps every screen's notch open and pages every screen
- Off-page widgets lie outside the open notch but inside the notch window (fitted to the widest page), and they are only clipped, which may not stop them receiving clicks
