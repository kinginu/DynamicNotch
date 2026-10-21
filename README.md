# DynamicNotch

[![CI](https://github.com/kinginu/DynamicNotch/actions/workflows/ci.yml/badge.svg)](https://github.com/kinginu/DynamicNotch/actions/workflows/ci.yml)

A notch companion app for Apple Silicon MacBooks: widgets and Live Activities in the notch, a
file tray with AirDrop, media controls, a timer in the style of the iOS Dynamic Island, and fan
control through the [FanControl](https://github.com/kinginu/FanControl) package. The app is an
original implementation. Releases are ad-hoc signed (there is no Developer ID, so they are not
notarized). Changes: [DynamicNotchApp/CHANGELOG.md](DynamicNotchApp/CHANGELOG.md).

## Requirements

- An **Apple Silicon** Mac running **macOS 26** or later (the notch UI is designed for MacBooks
  with a notch; fan control is Apple Silicon only).
- To build from source: **Xcode 26.6** (or later 26.x) and
  [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

## Install

1. Download `DynamicNotch-<version>.zip` from the
   [latest release](https://github.com/kinginu/DynamicNotch/releases/latest) (and, to check it,
   `SHA256SUMS.txt`; see [Verify the download](#verify-the-download)).
2. Unzip it (double-click, or `ditto -x -k DynamicNotch-<version>.zip .`).
3. Move `DynamicNotch.app` to `/Applications` (replace the old copy when updating).
4. Remove the quarantine flag:

   ```sh
   xattr -dr com.apple.quarantine /Applications/DynamicNotch.app
   ```

   The app is signed ad hoc, not with a Developer ID, and is not notarized, so Gatekeeper refuses
   to open a downloaded copy ("cannot be opened" / "damaged") until the flag the browser added is
   removed. Only do this for a download whose checksum you have verified.
5. Open DynamicNotch. It lives in the notch and the menu bar (no Dock icon).
6. Grant permissions when a widget first asks for them (Calendars, Reminders, Camera, Microphone,
   Location, Bluetooth, Accessibility, Input Monitoring, Automation); each one is needed only by
   the widgets that use it, and Settings shows what is granted.
7. **Fan control** (optional): open Settings ▸ Fan Control ▸ General and click
   **Install Helper…**, then enter your administrator password. Or, in Terminal:

   ```sh
   sudo /Applications/DynamicNotch.app/Contents/Resources/manual-install/install.sh /Applications/DynamicNotch.app
   ```

   Reading temperatures and fan speeds needs no helper; changing fan speeds does.

**After every update, install the helper again** (button or command above): the helper only
accepts the exact build it was installed for (it pins the app's code-signature hash, cdhash), so
a new build is refused until it is reinstalled. Settings says when this is needed.

To remove the helper: **Uninstall Helper…** in the same place, or
`sudo /Applications/DynamicNotch.app/Contents/Resources/manual-install/uninstall.sh /Applications/DynamicNotch.app`.
The same installer scripts are attached to each release as `manual-install.tar.gz`.

### Verify the download

Each release lists the SHA-256 of its files in `SHA256SUMS.txt`. In the download folder:

```sh
shasum -a 256 -c SHA256SUMS.txt --ignore-missing
# DynamicNotch-<version>.zip: OK
```

After unzipping, `codesign --verify --deep --strict /Applications/DynamicNotch.app` checks that
the bundle is intact (an ad-hoc signature proves integrity, not who built it; the checksum file
and the release page are what tie it to this repository's release workflow).

## Fan control helper

Fan **reads** need no privileges. **Writes** go through a root LaunchDaemon, which is installed by
hand instead of through `SMAppService` (no Developer ID is used). The installer is bundled in the
app at `Contents/Resources/manual-install/`; from a source build:

```sh
M=DynamicNotchApp/.derivedData/Build/Products/Debug/DynamicNotch.app/Contents/Resources/manual-install
APP=DynamicNotchApp/.derivedData/Build/Products/Debug/DynamicNotch.app
$M/install.sh --dry-run --app "$APP"   # preview, changes nothing
sudo $M/install.sh --app "$APP"        # install; re-run after EVERY rebuild (the helper pins the app's cdhash)
$M/status.sh --app "$APP"              # read-only status
sudo $M/uninstall.sh --app "$APP"      # remove
```

(`FanControl/Support/manual-install/` in the checkout holds the same scripts.) Read the
FanControl safety model and helper documentation before using fan control:
[FanControl/README.md](FanControl/README.md), [FanControl/docs/helper.md](FanControl/docs/helper.md).
How the app hosts the package (glue files in `DynamicNotchApp/Sources/FanControlGlue/`, hook
points, helper target, the bundled installer and its button) is described in
[DynamicNotchApp/docs/fan-control-integration.md](DynamicNotchApp/docs/fan-control-integration.md).

## Build from source

FanControl is a git submodule at `FanControl/` (pinned to a tag), and the app's `project.yml`
refers to it as `../FanControl`. Network access is needed on the first build, to fetch the
`mediaremote-adapter` package.

```sh
git clone --recurse-submodules https://github.com/kinginu/DynamicNotch.git   # or: git submodule update --init
cd DynamicNotch/DynamicNotchApp
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer   # if xcode-select points at the Command Line Tools
xcodegen generate                       # project.yml is the source of truth; the .xcodeproj is not committed
xcodebuild -project DynamicNotch.xcodeproj -scheme DynamicNotch -configuration Debug \
  -derivedDataPath .derivedData build CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES
open .derivedData/Build/Products/Debug/DynamicNotch.app
```

The build produces the app and the embedded `FanControlHelper` (an Xcode Command Line Tool
target), both ad-hoc signed with Hardened Runtime. Then install the helper for that build as
above.

`DynamicNotchApp/Package.swift` is a Command Line Tools harness that compiles the app sources as a
library and runs the unit tests without Xcode (`swift build`, `swift test`).

## Checks

```sh
scripts/check.sh            # everything: app build + tests, harness, FanControl, strings lint, shellcheck
scripts/check.sh --fast     # skip the Xcode build and the app's Xcode tests
scripts/check.sh --list     # step names
```

The script never installs anything, never uses `sudo`, never writes to the SMC and never launches
the app. CI ([.github/workflows/ci.yml](.github/workflows/ci.yml), GitHub's `macos-26` runner with
Xcode 26.6) runs the `--fast` checks and the Xcode Debug build with the unit tests on every pull
request; `main` only accepts pull requests that pass them.

## Releases

Releases are cut from tags. `scripts/tag-release.sh X.Y.Z` first bumps the version in
`DynamicNotchApp/project.yml` on a branch (merge it through a pull request), then, run again on
the updated `main`, creates the tag `vX.Y.Z`; it prints the push commands and never pushes.
Pushing the tag starts [.github/workflows/release.yml](.github/workflows/release.yml): it builds
the Release configuration with that version, signs it ad hoc with Hardened Runtime, and publishes
`DynamicNotch-X.Y.Z.zip`, `manual-install.tar.gz` and `SHA256SUMS.txt` with the notes of the
`## [X.Y.Z]` section of the CHANGELOG (`scripts/release-notes.sh`; no section, no release).

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
| `scripts/` | `check.sh` (all checks), `tag-release.sh` and `release-notes.sh` (releases) |
| `.github/workflows/` | CI and the release workflow |
| `docs/` | Reference notes (iOS timer, menu bar items), a review log and widget screenshots |
| `THIRD-PARTY-NOTICES.md` | Third-party components and services |

## Third-party material

The app bundles no assets from other apps; see [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)
for the packages and web services it uses. Do not add or distribute third-party app assets
(images, videos, localizations, shaders, …) in this repository.

## License

MIT; see [LICENSE](LICENSE). FanControl is MIT-licensed as well (its own repository), and the
dependencies' licenses are in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
