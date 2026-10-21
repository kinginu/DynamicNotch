# DynamicNotch

A notch companion app for Apple Silicon MacBooks: widgets and Live Activities in the notch, a
file tray with AirDrop, media controls, a timer in the style of the iOS Dynamic Island, and fan
control through the [FanControl](https://github.com/kinginu/FanControl) package. The app is an
original implementation. It is built locally and ad-hoc signed; no binaries are distributed.

Version **1.0.0** — see [DynamicNotchApp/CHANGELOG.md](DynamicNotchApp/CHANGELOG.md).

## Requirements

- An **Apple Silicon** Mac running **macOS 26** or later (the notch UI is designed for MacBooks
  with a notch; fan control is Apple Silicon only).
- **Xcode 26.6** (or later 26.x) and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
  (`brew install xcodegen`).
- Network access on the first build, to fetch the `mediaremote-adapter` package.

## Getting the sources

FanControl is a git submodule at `FanControl/` (pinned to its `v1.0.0` tag), and the app's
`project.yml` refers to it as `../FanControl`. Clone with submodules:

```sh
git clone --recurse-submodules https://github.com/kinginu/DynamicNotch.git
# or, in an existing clone:
git submodule update --init
```

## Building

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer   # if xcode-select points at the Command Line Tools
cd DynamicNotchApp
xcodegen generate                       # project.yml is the source of truth; the .xcodeproj is not committed
xcodebuild -project DynamicNotch.xcodeproj -scheme DynamicNotch -configuration Debug \
  -derivedDataPath .derivedData build CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES
open .derivedData/Build/Products/Debug/DynamicNotch.app
```

The build produces the app and the embedded `FanControlHelper` (an Xcode Command Line Tool
target), both ad-hoc signed with Hardened Runtime.

`DynamicNotchApp/Package.swift` is a Command Line Tools harness that compiles the app sources as a
library and runs the unit tests without Xcode (`swift build`, `swift test`).

## Checks

```sh
scripts/check.sh            # everything: app build + tests, harness, FanControl, strings lint, shellcheck
scripts/check.sh --fast     # skip the Xcode build and the app's Xcode tests
scripts/check.sh --list     # step names
```

The script never installs anything, never uses `sudo`, never writes to the SMC and never launches
the app.

## Fan control helper (manual install)

Fan **reads** need no privileges. **Writes** go through a root LaunchDaemon, which this build
installs by hand instead of through `SMAppService` (no Developer ID is used):

```sh
H=FanControl/Support/manual-install
APP=DynamicNotchApp/.derivedData/Build/Products/Debug/DynamicNotch.app
$H/install.sh --dry-run --app "$APP"   # preview, changes nothing
sudo $H/install.sh --app "$APP"        # install; re-run after EVERY rebuild (the helper pins the app's cdhash)
$H/status.sh --app "$APP"              # read-only status
sudo $H/uninstall.sh --app "$APP"      # remove
```

Read the FanControl safety model and helper documentation before using fan control:
[FanControl/README.md](FanControl/README.md), [FanControl/docs/helper.md](FanControl/docs/helper.md).
How the app hosts the package (glue files in `DynamicNotchApp/Sources/FanControlGlue/`, hook
points, helper target, manual install) is described in
[DynamicNotchApp/docs/fan-control-integration.md](DynamicNotchApp/docs/fan-control-integration.md).

## Network services

The app talks to three free web services, each only from the widget that needs it, and sends no
account, device or usage data to them; requests carry only what is listed here (plus the
Mac's IP address, as any HTTPS request does). The **Weather** widget calls
[Open-Meteo](https://open-meteo.com/) (free for non-commercial use, data under CC BY 4.0): the
forecast request sends the chosen place's latitude and longitude (4 decimals; from Location
Services only if you allow it) and the forecast fields it wants, and the city search sends the text you type. The
**Calculator** widget fetches currency reference rates from
[Frankfurter](https://www.frankfurter.app/) (`latest?from=USD`, no user data; cached for an hour).
The **Network** widget asks [ipify](https://www.ipify.org/) for your public IP address only when
"Show public IP address" is turned on (off by default). Nothing else leaves the Mac; see
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) for the services' terms.

## Layout

| Path | Contents |
|---|---|
| `DynamicNotchApp/` | The app: XcodeGen spec, sources (including the Fan Control glue in `Sources/FanControlGlue/`), tests, the Command Line Tools harness, support scripts, docs and the build log |
| `FanControl/` | Submodule: the FanControl package (MIT) |
| `scripts/check.sh` | All checks in one script |
| `docs/` | Reference notes (iOS timer, menu bar items), a review log and widget screenshots |
| `THIRD-PARTY-NOTICES.md` | Third-party components and services |

## Third-party material

The app bundles no assets from other apps; see [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)
for the packages and web services it uses. Do not add or distribute third-party app assets
(images, videos, localizations, shaders, …) in this repository.

## License

MIT; see [LICENSE](LICENSE). FanControl is MIT-licensed as well (its own repository), and the
dependencies' licenses are in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
