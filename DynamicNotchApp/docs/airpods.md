# AirPods listening mode (F7, 2026-10-21)

The Audio widget shows a listening-mode control (Off / Transparency / Adaptive / Noise Cancellation)
below the output list when AirPods with listening modes are the current output. Settings ▸ Widgets ▸
Audio has the on/off toggle, the Accessibility permission row and a "Read Current Mode" button.

Code: `Sources/AirPodsNoiseControl.swift` (modes, model detection, Sound-menu parser, service),
`Sources/AirPodsControlCenterDriver.swift` (Accessibility side), `Sources/AirPodsListeningModeViews.swift`
(widget row, settings section). Tests: `Tests/DynamicNotchAppTests/AirPodsNoiseControlTests.swift`
(`swift test --filter AirPods`; a fake driver and a fake permission, Control Center is never touched).
Strings: `Support/strings/airpods.json`. Hooks in existing files are marked `// F7:`.

## Approach and why

macOS has no public API for the listening mode. Two routes exist:

| Route | What it is | Used? |
|---|---|---|
| Accessibility (AXUIElement) on Control Center's Sound menu | Open the Sound menu extra, press the listening-mode checkbox under the AirPods row, close the menu. The same thing a person does; used by open-source tools (Raycast "AirPods Noise Control" AppleScript, the `AncProbe` / `AncController` Swift code in dchersey/air-defense, Keyboard Maestro macros). | **Yes** |
| Private AAP (Apple Accessory Protocol) over Bluetooth / private CoreBluetooth | Talks to the AirPods directly; no UI. | **No** (not allowed in this project) |

Costs of the Accessibility route, accepted:

- The Sound menu is visible for a moment (≈ 0.5–1.5 s) on each read or switch. The driver closes it again
  on every exit path: the close is deferred before the first press, so it also runs when AXPress reports an
  error but opens the menu anyway (`kAXErrorCannotComplete` is common on menu extras; the AX window count,
  not the press result, decides whether the menu opened). If the menu was not seen opening, `close` watches
  ≤ 1 s for a late one (slow Control Center). It closes with `AXCancel` on the menu window once (not a toggle),
  then by re-pressing the Sound item; after each attempt it waits ≤ 1 s for the window to actually leave
  AXWindows (the closing window stays listed during its fade, and pressing the toggle again then would reopen
  the menu), and gives up after 4 s. Nothing is read in the background: the mode is read only when the user
  switches it or chooses "Read Current Mode" (widget context menu or Settings). Until then the control
  shows no selection.
- Accessibility permission through `PermissionCenter` (`.accessibility`; the settings row is
  `PermissionStatusRow(kind: .accessibility)`, shared with the menu-bar feature). With ad-hoc signing, each rebuild has a new cdhash and macOS may drop the grant.
- The Sound item must be in the menu bar (System Settings ▸ Control Center ▸ Sound: "Always Show" or
  "Show When Active"); otherwise `soundMenuNotFound` with a hint. Going through the Control Center
  panel (tile `controlcenter-volume` → "show details") is described by air-defense but is not implemented
  (more UI, more moving parts).
- Labels are matched in English (the user's system is en-US), plus unverified Japanese guesses.

Rate limiting: one operation at a time on a background serial queue; at least 1 s between two menu
openings; clicks while a switch runs are coalesced (only the latest is applied; the clicked mode is shown at
once as pending). A read never replaces a switch: "Read Current Mode" is ignored (and disabled in the
widget's context menu) while the device has a request waiting or running, and a read that still arrives
during the rate-limit wait loses to the waiting switch (`AirPodsNoiseControlService.preferred`). Nothing
runs while the screen is locked (`CGSSessionScreenIsLocked`).

Fallback without Accessibility access: the widget row shows "Open Sound Settings" (System Settings ▸ Sound),
Settings shows the Accessibility `PermissionStatusRow` ("Allow Accessibility Access": system prompt the first
time, then "Open System Settings").

## Detection

The row appears when the default output (CoreAudio, `AudioDevicesManager`) is a Bluetooth device and
`AirPodsModel.detect` says it has listening modes:

1. Bluetooth product id (vendor 0x004C) from `system_profiler SPBluetoothDataType -json`, looked up once per
   address (`AirPodsProductIDLookup`). A found id, or a listed device that is not Apple's, is cached for the
   session. A failed lookup (system_profiler failed or timed out) or one that does not list the address yet
   (it ran before a just-connected device appeared) is retried after 30 s, at most 5 times, and only then
   cached as "not found" — otherwise AirPods 4 (ANC), which are recognized by product id only, would lose the
   row until relaunch. The address comes from the CoreAudio UID (`18-3F-70-69-CE-57:output` → `18:3f:70:69:ce:57`;
   **the UID format is an assumption, not verified here** — the AirPods were not connected).
   | Product id | Model | Modes | Source |
   |---|---|---|---|
   | 0x2024 | AirPods Pro 2 (USB-C) | Off*, Transparency, Adaptive, NC | **verified on this Mac** (`system_profiler`) |
   | 0x2014 | AirPods Pro 2 (Lightning) | same | community |
   | 0x2027 | AirPods Pro 3 | same | community, unsure |
   | 0x200E | AirPods Pro | Off*, Transparency, NC | community |
   | 0x200A, 0x201F | AirPods Max (Lightning, USB-C) | Off, Transparency, NC | community |
   | 0x201B | AirPods 4 with ANC | Off*, Transparency, Adaptive, NC | community, unsure |
   | 0x2002, 0x200F, 0x2013, 0x2019 | AirPods 1/2/3/4 | none (no row) | community |
   \* AirPods Pro / 4 show "Off" only when it is enabled in the AirPods' settings.
2. Otherwise the name: contains "AirPods Pro" or "AirPods Max".

After the first read the segments are the modes the Sound menu actually offered.

## Sound-menu structure the parser expects (macOS 26)

From the open-source tools above (not inspected on this Mac, see below):

- Each output device is an `AXCheckBox` with `AXIdentifier` `sound-device-<name>`, `AXDescription` starting
  with the name (`AirPods Pro, 84%`), `AXValue` 1 = current output.
- Everything belonging to the device shares that identifier: an `AXDisclosureTriangle`, and — while it is
  the output and expanded — one checkbox per listening mode (`Off`?, `Transparency`, `Adaptive`,
  `Noise Cancellation`), then Conversation Awareness `Off` / `On`.
- The parser takes the consecutive run of mode checkboxes; `Off` counts only as the first item, so the
  Conversation Awareness `Off` is never pressed. If the section is collapsed, the driver presses the
  disclosure triangle once. Device rows are never pressed (that would switch the output).

## Verified read-only on this Mac (2026-10-21 00:00, MacBook Pro Mac14,9, macOS 26.5.2)

- The AirPods ("<owner>’s AirPods Pro") are paired: vendor 0x004C, product id **0x2024**, minor type
  Headphones (`system_profiler SPBluetoothDataType`). They were **not connected** during the session, so the
  listening-mode items could not be seen and no mode was read or changed.
- Control Center's `AXExtrasMenuBar` has the Sound item with `AXIdentifier` **`com.apple.menuextra.sound`**
  (`AXDescription` "Sound", `AXValue` "0%", actions AXPress / AXCancel) and the Bluetooth item
  `com.apple.menuextra.bluetooth`; `AXMenuBar` is nil. The identifier is locale-independent, so the driver
  does not need the localized "Sound" name (unlike the AppleScript tools).
- The terminal process was Accessibility-trusted. The screen was **locked** while probing: pressing the Sound
  item returned success but the menu's tree was not reachable (`AXWindows` returned one element that is the
  application itself), so the menu contents could not be dumped. Hence the driver refuses to run while the
  screen is locked.
- Probe scripts (read-only: they list attributes and open/close the Sound menu without pressing anything in
  it) were kept outside the repository.

## To verify (needs the AirPods connected and the screen unlocked)

1. The UID format of the AirPods output (`AudioDevice.uid`) — needed for the product-id lookup.
2. The Sound menu tree with the AirPods as output: identifiers, labels, whether the listening modes are
   inline or behind the disclosure triangle, which `AXWindows` entry is the menu.
3. "Read Current Mode", then each segment, watching that the menu closes every time and the Nook stays open
   (the menu takes key status for a moment).
4. With Sound set to "Show When Active": whether the item is present while AirPods are the output.
5. macOS 27: the menu-bar items reportedly move to `com.apple.MenuBarAgent`; the driver looks there too,
   but the menu windows are still taken from Control Center.

## Strings

English only, listed in `Support/strings/airpods.json` (mode names, widget / settings labels, the
`AirPodsNoiseControlError.message` texts); `merge-strings.py` regenerates Localizable.strings and
`lint-strings.py` checks them.
