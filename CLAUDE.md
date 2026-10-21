# CLAUDE.md — DynamicNotch

Notch companion app for Apple Silicon MacBooks (macOS 26, Xcode 26.6, XcodeGen). Built locally and
ad-hoc signed; no binaries are distributed. Start with [README.md](README.md); the detailed engineering log
(Japanese) is [DynamicNotchApp/BUILD-LOG.md](DynamicNotchApp/BUILD-LOG.md).

## Layout

| Path | Contents |
|---|---|
| `DynamicNotchApp/project.yml` | XcodeGen spec — the source of truth. `.xcodeproj` is generated and git-ignored; `Support/Info.plist` and `Support/DynamicNotch.entitlements` are generated **and** committed (run `xcodegen generate` after editing `project.yml`). |
| `DynamicNotchApp/Sources/`, `App/` | App sources; `App/` holds `@main` and is compiled only by the Xcode target. `Sources/FanControlGlue/` is the Fan Control host glue (Xcode targets only; excluded from the CLT harness) — see `DynamicNotchApp/docs/fan-control-integration.md` |
| `DynamicNotchApp/Tests/` | Swift Testing unit tests, shared by the Xcode test target and the CLT harness |
| `DynamicNotchApp/Package.swift` | Command Line Tools harness (app sources as a library + tests) |
| `DynamicNotchApp/Support/` | `merge-strings.py`, `lint-strings.py`, `strings/*.json`, `make-app-icon.swift` |
| `FanControl/` | **Git submodule** (github.com/kinginu/FanControl, pinned to a tag). `project.yml` uses `../FanControl`; `Sources/Support/SettingsStorage.swift` is a symlink into it. Change FanControl in its own repository, tag it, then bump the submodule here. |
| `scripts/check.sh` | Every check in one script |

## Checks

Run `scripts/check.sh` (or `--fast`, or named steps from `--list`) before committing. It sets
`DEVELOPER_DIR` to Xcode when present, and never installs anything, uses `sudo`, writes the SMC
or launches the app. FanControl must stay at **zero warnings**.

## Rules

- **Strings:** the UI is English only (no `ja.lproj` or other localizations).
  `Localization/en.lproj/Localizable.strings` is generated — never edit it by hand. Add keys to
  `Support/strings/<feature>.json` (Fan Control's labels: `fan-control.json`), then run `python3 -I Support/merge-strings.py` and `python3 -I Support/lint-strings.py` from
  `DynamicNotchApp/`.
- **Widgets:** a new widget gets the next free tag in `NookWidget` and must be registered in
  every registry: `NookWidget`, the grid / pager (`Sources/Support/NookWidgetGrid.swift`),
  `WidgetsSettingsTabView` and `DebugHooks`. Keep tags stable (they are persisted). Use system
  materials, SF Symbols and standard controls (Apple-native look).
- **Helper protocol:** the app ↔ helper XPC contract lives in FanControl
  (`FanControlHelperConstants.protocolVersion`, currently 2). Any change to selectors, argument
  types, error codes or the write allowlist bumps the version in FanControl first. After every
  app rebuild the user must re-run `sudo FanControl/Support/manual-install/install.sh --app …`
  (the helper pins the app's cdhash).
- **Safety:** never run `sudo`, never write to the SMC, and never install or restart the helper
  from a session. Fan writes need the user's explicit confirmation, step by step.
- **Third-party material:** do not add assets from other apps (images, videos, localizations,
  shaders, binaries). Record new packages and web services in `THIRD-PARTY-NOTICES.md`.
- **Commits:** small and focused. The message ends with exactly one footer line:
  `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` — no `Claude-Session:` line.
