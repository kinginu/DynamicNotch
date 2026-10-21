# Automation: URL scheme, Shortcuts and `dnctl`

DynamicNotch can be driven from outside the notch in three ways. All three build the same
`AutomationCommand` and run it through `CommandRouter.perform(_:)`, so they share one set of rules.

| Surface | Entry point | Source |
|---|---|---|
| URL scheme `dynamicnotch://` | `AppDelegate.application(_:open:)` → `URLCommandRouter` | `Sources/Automation/URLCommandRouter.swift` |
| App Intents / App Shortcuts (Shortcuts, Spotlight, Siri) | `AppIntent.perform()` | `Sources/Automation/AutomationIntents.swift` |
| `dnctl` command-line tool | opens a `dynamicnotch://` URL | `Tools/dnctl/main.swift` |

Parsing: `Sources/Automation/AutomationCommand.swift`. Policy: `Sources/Automation/CommandRouter.swift`.
Side effects: `Sources/Automation/LiveAutomationActions.swift`. These call the existing managers
(`FanControlProfiles.apply`, `NookTimersStore`, `DynamicNotchState`, `CaptureManager`,
`KeepAwakeManager`, `PomodoroStore`). They add no new state and no new SMC write path.

## Commands

Verbs, slugs and widget ids ignore case, spaces, `-`, `_` and `.`. `dynamicnotch:profile/boost`,
`dynamicnotch:///profile/boost` and `dynamicnotch://profile/boost` are equivalent. Query parameter
names ignore case.

| URL | Does | Needs |
|---|---|---|
| `dynamicnotch://profile/<slug>` | Applies a fixed fan profile. Slugs: `automatic`, `constant-quiet`, `constant-high`, `boost`, `max`, `custom-1`, `custom-2`. A default name such as `Constant%20Quiet` also works. Short aliases (`auto`, `smc`, `quiet`, `high`, `maximum`, `full`) work too, unless a custom slot has that name (see Rules) | Fan Control turned on |
| `dynamicnotch://profile/<uuid>` | Applies the fixed profile with this id (`FanProfile.BuiltInID`) | Fan Control turned on |
| `dynamicnotch://profile/<name>` | Applies the fixed profile with this display name, for example a renamed custom slot. Case- and diacritic-insensitive | Fan Control turned on |
| `dynamicnotch://fan/auto` | Hands the fans back to the SMC: `FanControlManager.restoreDefaultControl()`, the same call as Settings ▸ Fan Control ▸ Return to Automatic. Always runs, also when Automatic is already selected | Fan Control turned on |
| `dynamicnotch://timer/start?minutes=25&label=Tea` | Starts a timer. Takes `hours=`, `minutes=` and `seconds=` (they add up; fractions allowed) or `timer/start/<minutes>`. 1 s to 23:59:59 after rounding to whole seconds; the range is checked before the value becomes an `Int`, so huge values such as `minutes=1e300` are an error, not a crash. Label: at most 100 characters | — |
| `dynamicnotch://timer/stop[?label=Tea]` | Cancels every timer, or only the ones with this label. Also silences their alerts | — |
| `dynamicnotch://notch/open`, `notch/close` | Opens the Nook on the notch under the pointer (else the main screen's), or closes every notch | — |
| `dynamicnotch://widget/<id>/show` | Switches the Nook to the page that holds the widget (`NookWidgetPager.show(page:)`, not animated) and opens it. `<id>` is a `NookWidget` raw value or name: `keepAwake` / `keep-awake` / `Keep%20Awake`, `pomodoro` / `focus`, `mirror` / `camera`, `fan`, and so on | The widget is in the Nook |
| `dynamicnotch://capture/area`, `window`, `screen` | Takes a screenshot, same as the Capture widget's buttons. Uses its destination and delay settings | Settings ▸ Nook ▸ Widgets ▸ Capture ▸ Allow automation to take screenshots (off by default); no capture already running |
| `dynamicnotch://keepawake/on[?duration=15m\|1h\|2h\|indefinite]` | Starts Keep Awake. Without `duration` it uses the last duration; if Keep Awake is already on, the session keeps running | The Keep Awake widget is in the Nook |
| `dynamicnotch://keepawake/off`, `keepawake/toggle` | Stops or toggles Keep Awake | The Keep Awake widget is in the Nook |
| `dynamicnotch://pomodoro/start`, `pause`, `skip` | Starts or resumes, pauses, or skips to the next phase. Alias: `focus/…`; `resume` means `start` | The Focus widget is in the Nook |

### Rules

- **Fan commands use the existing paths only.** `profile/…` calls `FanControlProfiles.apply`, the
  same call as the Fan Control widget's selector. `fan/auto` and `profile/automatic` call
  `FanControlManager.restoreDefaultControl()`, the same call as Settings ▸ Fan Control ▸ Return to
  Automatic. The usual safety rules still apply: the helper's write policy, the emergency override
  and the restore on quit. The router refuses fan commands while Settings ▸ Fan Control ▸ Enable is
  off. A profile that is already active (selected, with the write session open) is not applied
  again, as in the widget. Automatic is the exception: it always runs, which also hands a fan still
  in manual mode back to the SMC and closes a write session left open.
- **Fans are discovered on demand.** The fan list is filled by the first poll. When nothing has
  polled yet (auto-start monitoring off, or a cold launch from a URL or intent), a fan command runs
  one poll (`refreshNow()`, which does not start monitoring) and waits up to about 2 s for the
  fans before it reports "No fans found."
- **Only the seven fixed profiles can be applied.** Canonical slugs and default names are checked
  before display names. A custom slot renamed "Boost" is therefore reached as `custom-1` or by its
  UUID, not as `boost`. The short aliases (`auto`, `smc`, `quiet`, `high`, `maximum`, `full`) come
  last: a custom slot renamed "Quiet" is what `profile/quiet` applies, and without such a name
  `quiet` still means Constant Quiet (`FanProfileReference.aliasFallback`).
- **URL captures need the user's opt-in.** Any process can open a `dynamicnotch://` URL, so
  `capture/…` from a URL (and therefore from `dnctl`) is refused with "Screenshots from URLs are
  off" unless Settings ▸ Nook ▸ Widgets ▸ Capture ▸ Allow automation to take screenshots is on
  (`automationAllowsCaptures`, default off). The router applies this to `AutomationSource.url`
  only. App Intents run with `.intent`: they are the user's own Shortcuts, and an intent that
  captures must ask first with `requestConfirmation` (no capture intent exists yet).
- **Keep Awake and Focus need their widget in the Nook.** Their managers end a session when the
  widget is removed, because the widget is the only place with all their controls. The router
  keeps that rule.
- **`widget/<id>/show` shows the widget's page.** With widget pages, the pager is switched to the
  page that holds the widget before the notch opens.
- **A notch opened by a command closes in the usual way**, through the hover state machine. It
  closes when the pointer enters and then leaves the notch, or on `notch/close`.

## URL scheme

`project.yml` registers the scheme (`CFBundleURLTypes`: `dynamicnotch`, role Viewer).
`AppDelegate.application(_:open:)` passes the URLs to `URLCommandRouter.shared.handle(_:)`. The
router runs them one at a time, in the order they arrive: a fan profile apply finishes before the
next URL runs. The scheme cannot send a reply. The app logs each outcome, and beeps when a
command fails:

```sh
/usr/bin/log stream --predicate 'subsystem == "com.example.dynamicnotch.DynamicNotch" AND category == "automation"'
```

Any process, or a web page after the browser asks for confirmation, can open a `dynamicnotch://`
URL. The surface is limited on purpose. It can apply only the fixed fan profiles, under the normal
safety policy. Screenshots are refused unless the user turned on Allow automation to take
screenshots; when on, they go to the destination set in the Capture widget's settings. With the
Clipboard destination any app can read the result, which is why the setting is off by default.
No command returns data.

## Shortcuts (App Intents)

| Intent | Parameters | Runs |
|---|---|---|
| Set Fan Profile | Profile (`FanProfileChoice` AppEnum: Automatic, Constant Quiet, Constant High, Boost, Max, Custom 1, Custom 2) | `profile/<slug>` |
| Return Fans to Automatic | — | `fan/auto` |
| Start Timer | Minutes (1–1439), Label (optional) | `timer/start` |
| Toggle Keep Awake | Mode (`KeepAwakeIntentMode` AppEnum: Toggle, On, Off; default Toggle) | `keepawake/toggle\|on\|off` |
| Start Focus Session | — | `pomodoro/start` |

`DynamicNotchShortcuts` (an `AppShortcutsProvider`) offers all five as App Shortcuts. Every
phrase contains the app name. A command that fails throws `AutomationIntentError`, and Shortcuts
shows its message.

**Discovery.** Shortcuts reads the metadata (`Metadata.appintents`) that Xcode extracts at build
time. A locally built, ad-hoc signed app may have to be launched once before Shortcuts lists the
intents. It may also have to be in `/Applications`, and Spotlight may need to have indexed it.
Discovery of an ad-hoc signed build has not been verified yet.

## `dnctl`

`dnctl` is a small SwiftPM executable in the CLT harness (`Package.swift`). It uses Foundation and
AppKit only and does not link the app sources. It turns its words into a URL and opens it, without
activating the app:

```sh
cd DynamicNotchApp
swift run dnctl profile boost                       # dynamicnotch://profile/boost
swift run dnctl fan auto
swift run dnctl timer start minutes=25 label="Green tea"
swift run dnctl timer stop
swift run dnctl widget keep-awake show
swift run dnctl keepawake on duration=1h
swift run dnctl --print pomodoro start              # print the URL, do not open it
swift run dnctl profile Late Night                  # words after `profile` form one name: profile/Late%20Night
swift run dnctl 'dynamicnotch://capture/area'       # pass a URL through unchanged
swift run dnctl --bundle-id <id> notch open         # send to a specific app (for example a dev build)
```

Positional words become the host and the path; after `profile` the remaining words are joined with
spaces into one name (a `/` inside a name stays encoded as `%2F`). `key=value` words become the query, percent-encoded
(`&`, `=` and `+` in values are escaped). `dnctl` cannot report the command's result, because the
scheme has no reply channel; the result is in the app's log. It reports only whether an app took
the URL. Exit codes: 0 handed over, 64 usage, 69 no handler or unknown bundle id, 75 timeout.
To install: `swift build -c release --product dnctl`, then copy `.build/release/dnctl` onto your `PATH`.

## Tests

`Tests/AutomationTests/AutomationCommandTests.swift` (Swift Testing) covers the points below. It is
part of the single `DynamicNotchAppTests` target over `Tests/**`, in both the harness and Xcode:

- parsing of every command, its aliases, bounds and errors, and the alternative URL forms
- round trips of the canonical URL (`AutomationCommand.url`)
- profile name matching
- the `CommandRouter` rules, with fake actions; no manager is touched (including the capture
  opt-in for URLs, `fan/auto` always restoring, and `widget/…/show` switching the page)
- durations that overflow `Int` (`minutes=1e300`, `hours=1e16`) are rejected, not trapped on

```sh
cd DynamicNotchApp
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --skip-update --filter Automation
# or, in Xcode: xcodebuild -project DynamicNotch.xcodeproj -scheme DynamicNotch test -only-testing:DynamicNotchAppTests
```

## Strings

The new user-facing strings are plain English literals: intent titles, descriptions, parameter
names, AppEnum case names, App Shortcut phrases and short titles, and the router's result and error
messages. The App Intents ones (titles, descriptions, parameter and type names, AppEnum cases,
short titles) are listed in `Support/strings/automation.json`, which `Support/merge-strings.py`
merges into `Localization/en.lproj` (identity entries; the app is English only).
`Support/lint-strings.py` must pass. The phrases and the router's messages are plain literals.

- Intent titles: Set Fan Profile, Return Fans to Automatic, Start Timer, Toggle Keep Awake, Start
  Focus Session.
- Parameters: Profile, Minutes, Label, Mode. Types: Fan Profile, Keep Awake Mode.
- AppEnum cases: Automatic, Constant Quiet, Constant High, Boost, Max, Custom 1, Custom 2; Toggle,
  On, Off.
- Summaries: "Set fan profile to …", "Start a … minute timer", "Keep Awake: …".
- App Shortcut short titles: Set Fan Profile, Fans to Automatic, Start Timer, Keep Awake, Start
  Focus Session. Phrases: "Set fan profile in DynamicNotch", "Set DynamicNotch fan profile to …",
  "Return fans to automatic in DynamicNotch", "Start a timer in DynamicNotch", "Toggle Keep Awake
  in DynamicNotch", "Start a focus session in DynamicNotch".
- Intent descriptions: the five one-line `IntentDescription`s in `AutomationIntents.swift`.
- Results and errors: the messages in `CommandRouter.swift` and `AutomationError.errorDescription`.
- Settings (Capture widget ▸ Automation section, `AutomationSettings.swift`): Automation, Allow
  automation to take screenshots, and its footnote. These are in `automation.json`.

## Leftovers

- `x-callback-url` style replies (`x-success`, `x-error`) are not implemented. `dnctl` therefore
  cannot print the command's result.
- `capture/record` (screen recording) is not exposed. Starting a recording from a URL, with no
  visible control in reach, seemed too easy to trigger by mistake.
- App Intents: the fan profile is an AppEnum of the seven fixed slots. A renamed custom slot is
  still listed under its default name.
- End-to-end delivery has not been checked on a running build: `application(_:open:)` under the
  SwiftUI app lifecycle, and Shortcuts discovery. The Xcode build does contain the URL type and
  `Metadata.appintents` (5 actions, 5 App Shortcuts, 2 enums). To check, run once:
  `log stream` (above), then `dnctl notch open`.
