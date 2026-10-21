# Volume / brightness HUD (F5, 2026-10-20)

A short HUD in the **closed notch** when the output volume, the built-in display's brightness or
the keyboard backlight changes: the `.hud` live activity, icon on the left of the camera housing,
a fill bar on the right, hidden 1.2 s after the last change. Key repeats and the CoreAudio
notifications that follow a key press update the same HUD (the bar animates), so holding a key
does not flicker.

Code: `Sources/HUDMonitor.swift` (detection, readers, presentation timer),
`Sources/HUDLiveActivityView.swift` (the two sides), `Sources/HUDSettings.swift` (settings + pane),
`Sources/Support/DebugHooks-HUD.swift` (DEBUG), `Support/strings/hud.json` (strings). Hooks marked
`// F5:` in `LiveActivities/LiveActivity.swift` (case `hud`), `LiveActivities/LiveActivityDescriptor.swift`
(descriptor: id `hud`, priority 95, `HUDLiveActivityView.sideWidth`, not configurable, gate
`.liveActivitiesSettings`), `LiveActivities/LiveActivitySelectionManager.swift` (battery override),
`LiveActivities/LiveActivityView.swift`, `LiveActivities/LiveActivityCenter.swift`
(`LiveActivitiesStartup`), `LiveActivitiesCustomizeSettingsTabView.swift` (HUD pane) and
`Support/PermissionCenter.swift` (`AppPermission.inputMonitoring`). The old media-key listener was
removed (see "Old listener" below).

## Settings

- Master switch: the existing **Settings ▸ Live Activities ▸ General ▸ "Volume & brightness HUD"**
  (`LiveActivitiesSettings.enableVolumeBrightness`, default on). The HUD also obeys
  "Show live activities in the closed notch".
- **Live Activities ▸ Customize ▸ HUD** (`HUDSettings`, key `hudSettings`): show for Volume /
  Display brightness / Keyboard backlight; "Watch the volume and brightness keys"; the
  Input Monitoring `PermissionStatusRow` (PermissionCenter `.inputMonitoring`: status from
  `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)`; it reported *denied* (not *unknown*) for the
  never-asked dev app, so — like Screen Recording / Accessibility — the first request is remembered
  (`permissionPrompted.inputMonitoring`) and the row shows **Request Access**
  (`CGRequestListenEventAccess()`, which adds the app to the list) until then, **Open System
  Settings** at `Privacy_ListenEvent` afterwards); a Sources section showing what each kind is currently driven by.
- Priority: `.hud` (95) is right after the FanControl alert (100; a safety alert keeps the notch)
  and above timers (90), battery, media …; it is
  not overridden by the "prefer battery while unplugged" rule. A counting timer moves to its
  minimal ring beside the HUD, like beside any other activity.

## Permissions

| What | Permission | Without it |
|---|---|---|
| Volume / mute (CoreAudio listeners) | none | — |
| Media keys via listen-only `CGEvent` tap (`NX_SYSDEFINED`) | **Input Monitoring** (`AppPermission.inputMonitoring`) | falls back to `NSEvent.addGlobalMonitorForEvents(matching: .systemDefined)` plus a pass-through `addLocalMonitorForEvents(matching: .systemDefined)` (see "Without Input Monitoring" below) |
| Brightness / keyboard level (`corebrightnessdiag` subprocess) | none | — |

**Without Input Monitoring.** The fallback is two `NSEvent` monitors. The global one sees only
events delivered to *other* apps, so a local one (which passes the event on unchanged) covers
events delivered to DynamicNotch itself, for example brightness keys pressed while Settings ▸ HUD
is frontmost. Limits of this mode: the monitors observe what the window server hands out; they are
not a session tap, so events that never reach an app's queue (secure input, such as a password
field, or keys another app's active tap swallows) are not seen, and whether real hardware keys
always arrive this way is still unconfirmed on this Mac (see Findings). Settings ▸ HUD ▸ Sources
shows "Keys if delivered" until the first key arrives. Granting Input Monitoring switches to the
listen-only tap.

The app never prompts on its own: the tap is created only when Input Monitoring is already
granted, and the prompt appears only from the Settings button. No Accessibility permission is
used (the tap is listen-only and never modifies or swallows an event). Ad-hoc builds lose the TCC
grant on every rebuild (the grant is tied to the cdhash), like the FanControl helper pin.

## Findings on Mac14,9 / macOS 26.5 (Apple M2 Pro, built-in XDR + 2 external displays)

Tested only in a development instance (bundle id `…DynamicNotch.dev.f5`, `DN_DEBUG_CHANNEL=f5`,
`DN_DEBUG_OFFSCREEN=1`, launched with `open` so TCC sees the app itself, not the shell). No volume,
brightness or keyboard value was changed and no real key was pressed (nobody at the keyboard), so
the end-to-end "press key → HUD" path is verified only up to the event monitor.

**Display brightness**

| Path | Result |
|---|---|
| `IODisplayGetFloatParameter(kIODisplayBrightnessKey)` | `0xe00002c7` (kIOReturnUnsupported) on `AppleARMBacklight` and on the three `IOMobileFramebufferShim`s; no `IODisplayConnect`, `AppleBacklightDisplay` or `AppleCLCD2` service exists |
| IORegistry `AppleARMBacklight` → `IODisplayParameters` | readable (single-property read), but **not the user brightness**: `brightness` 32768/65536 = 0.50, `rawBrightness` 1488/2047, `BrightnessMilliNits` 381794, all constant over 5 min of 2 s samples with auto-brightness on, while CoreBrightness reported 0.425 / 67.8 nits. `new-backlight-architecture = Yes` (DCP): the panel is driven elsewhere and these properties look like boot-time values |
| `/usr/libexec/corebrightnessdiag status-info` | **works**: plist on stdout, `CBDisplays/<uuid>/Display/DisplayServicesBrightness` = 0.4254 for the display with `DisplayServicesIsBuiltInDisplay = true` (also `DisplayServicesLinearBrightness`, `DisplayNitsKey`, `CBAutoBrightnessEnabled`). 26–120 ms per run in the app (36 ms typical). No permission needed |
| DisplayServices / CoreDisplay (`DisplayServicesGetBrightness`, `CoreDisplay_Display_GetUserBrightness`) | private frameworks — not used |

So the brightness level comes from `corebrightnessdiag` (an Apple diagnostic binary run as a
subprocess, its output format undocumented — it may change in a future macOS; then the HUD falls
back to the predicted / direction-only display). Reads happen only after a brightness or
illumination key (debounced 150 ms, one in flight, one seed read at launch), never by polling.
Only a missing tool turns the reads off for the session. Any other failure (the 2 s timeout, a
non-zero exit, a plist without the built-in values, e.g. a slow seed read during login) starts a
30 s cooldown (`HUDLevelReadScheduler.failureBackoff`): key presses in it show the prediction /
direction only, and the first key after it reads again; a successful read ends the failure state.
Until the read lands the bar shows a prediction: the last level ± 1/16 (⌥⇧: 1/64), the macOS step.

**Keyboard backlight**: IORegistry has `IOResources.KeyboardBacklight = Yes`, a vendor-page HID user
device "Keyboard Backlight" (usage page 0xFF00 / usage 0x0F, owned by CoreBrightness) and the PWM
node `kbd-backlight@0` (`enabled`, `high-period`, `low-period`, unverified whether they track the
level). No documented IOKit property carries the level. `corebrightnessdiag` reports
`CBKeyboards/<id>/CBKeyboardBacklightContainer/KeyboardBacklightBrightness` (0.0 here; the
backlight was `KeyboardBacklightSuppressed = true`, probably ambient light). Used the same way as
for the display.

**Volume**: default output "MacBook Pro Speakers"; the virtual main volume and mute are readable
without permission (0.0 / muted at test time, matching the Audio widget's reading). Listeners are
registered on the virtual main volume, the scalar on main / channels 1–2 and mute; change
notifications were not exercised (the volume was not changed).

**Media keys**

- Dev instance: `CGPreflightListenEventAccess()` = false, `AXIsProcessTrusted()` = false → key source
  = global `NSEvent` monitor (no prompt was shown; TCC only logged a Microphone preflight).
- Two synthetic `NX_SYSDEFINED` events were posted from the shell (one with an undefined subtype 90,
  one aux-button event, subtype 8, for key type 30, which is not a key; neither has any effect on
  the system): **both reached the global monitor without Input Monitoring or Accessibility**
  (`sysdefSeen` 0 → 1 → 2). Real hardware media keys travel the same NX_SYSDEFINED path, so the
  HUD should react to F1/F2 and F10–F12 without any permission; this needs a real key press to
  confirm (Settings ▸ Sources shows "Global event monitor, working" after the first key).
- The listen-only event tap path (taken when Input Monitoring is granted) compiled and is wired the
  same way but was not exercised (the dev app has no grant, and granting it would need the user).
- `hudkey:` (fed directly into `handleMediaKey`) confirmed the presentation: one `.hud` request
  (`requested=["hud"] visible=["hud"] current=hud`), the bar updated in place for repeats (0.7 →
  predicted 0.75 → read 0.425 → predicted 0.5 → read 0.425), hidden 1.2 s after the last key.

Snapshots (offscreen, 1×): `hudpreview:` writes `hud-notch-{volume-60,volume-0,volume-muted,
volume-unavailable,brightness-80,brightness-10,keyboard-50,keyboard-unknown}.png` and
`hud-settings.png`.

## Limitations

- **The system HUD is not hidden.** macOS has no public API for it. The known approaches are all
  unsafe or private: swallowing the media keys with an active event tap (needs Accessibility, and
  the app then has to change volume/brightness itself — brightness only through private
  DisplayServices/CoreDisplay; if the app hangs, the keys stop working), or killing / disabling
  `OSDUIHelper` / the Control Center OSD. Not implemented, by design.
- Display brightness and the keyboard backlight are driven by the **keys only**; changes made in
  Control Center, by auto-brightness or by other apps are not shown (polling `corebrightnessdiag`
  costs ≈ 0.1–0.3 s of a subprocess per read, too much to run continuously).
- The keyboard-backlight HUD needs illumination keys (`NX_KEYTYPE_ILLUMINATION_*`). Mac14,9's
  built-in keyboard has none (the level is set from Control Center), so on this Mac it only appears
  with an external keyboard that has those keys.
- External Apple keyboards that send brightness as F14/F15 (`keyDown` 107/113/144/145) are not
  watched: that needs a keyboard-event tap. Brightness of external displays (DDC) is out of scope.
- Volume changes from any source (Control Center, other apps, the Audio widget) show the HUD while
  the notch is closed; switching the output device does not.

## Old listener

An earlier `VolumeAndBrightnessListener` was started from `NotchView.SideEffectsModifier`'s
`onAppear`. Its `MediaKeyTap.start()` sets `interceptMediaKeys = true` on an
**active** (`.defaultTap`) session tap, and the tap callback returns `nil` for every media key while
that flag is set — i.e. once the app has Accessibility, the volume / brightness / play keys would be
swallowed and stop working system-wide. Without Accessibility `CGEvent.tapCreate` fails and nothing
happens, which is probably why it went unnoticed. F5 removed the call (`startBriVolKeyListener` in
NotchView, `_ = VolumeAndBrightnessListener.shared` in AppDelegate and the fan-control-integration.md (e) snippet)
and, since nothing else used them, the files `VolumeAndBrightnessListener`, `MediaKeyTap`,
`MediaKeyTapInternals`, `MediaKey`, `KeyEvent`, `KeyPressMode` and `EventTapError`. `HUDMonitor` is
the only media-key listener now. (`VolumeMonitor` / the `Indicator*` views are still used elsewhere
and were kept.)

## Strings (English only; localized keys in `Support/strings/hud.json`)

Settings pane (`HUDSettingsView`): "Volume & brightness HUD" (existing key), "Shows a short HUD in
the closed notch when the volume, display brightness or keyboard backlight changes.", "Show for",
"Volume", "Display brightness", "Keyboard backlight", "Keys", "Watch the volume and brightness keys",
"With Input Monitoring the volume, brightness and keyboard-backlight keys are read by a listen-only
event tap. Without it volume changes still show; the brightness keys work only if macOS delivers them
to the app's global event monitor.", "Input Monitoring" (also `AppPermission.title`), "Request Access",
"Media keys are read with a listen-only event tap.", "Not allowed. Volume
changes still show; the keys may not.", "Sources", "Media keys", "The system's own volume and
brightness HUD still appears: macOS has no public API to hide it."

Activity name (segmented picker in Customize): "HUD".

Source descriptions (verbatim `String`s, not localized): "Off", "Event tap (listen-only)",
"Event tap (listen-only), working", "Global event monitor (no key seen yet)",
"Global event monitor, working", "Unavailable", "CoreAudio: <device>", "No output device",
"Keys, level from corebrightnessdiag", "Keys, level unknown", "Keys, level read on first key",
"Keys if delivered, …", "Needs the keys", "Illumination keys, level from corebrightnessdiag",
"Illumination keys, level unknown".

Accessibility (verbatim): "Volume", "Display brightness", "Keyboard backlight", "Muted", "Unknown",
"<n>%".

## DEBUG hooks

`Support/DebugHooks-HUD.swift`, registered with `DebugCommandRegistry` by `HUDMonitor.start()`
(log lines are public: `log stream --predicate 'category == "hud-debug"'`):
`hudstate`, `hudkey:<NX_KEYTYPE>`, `hudsim:<volume|muted|brightness|keyboard>[:<level|none>]`,
`hudpreview:<dir>`.
