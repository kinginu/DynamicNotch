# Third-party notices

DynamicNotch 1.0.0 is built from its own sources, the [FanControl](https://github.com/kinginu/FanControl)
package (MIT, © 2026 kinginu, included as the `FanControl/` submodule) and the components listed
below.

## No third-party app assets

The app contains **no assets taken from third-party apps**: no asset catalogs, images, videos,
animations, shaders, localizations or other resources from any other application. The app icon is
drawn by `DynamicNotchApp/Support/make-app-icon.swift`; the only bundled resources are that icon,
the generated `en.lproj/Localizable.strings` and the resource bundle that SwiftPM builds from
`mediaremote-adapter`.

## Swift packages

### mediaremote-adapter

- Source: <https://github.com/ejbills/mediaremote-adapter>, revision
  `5b6afde3f501a3da567e23bf7f23d562938a1809` (pinned in `DynamicNotchApp/Package.resolved` and
  `project.yml`). It is a fork of <https://github.com/ungive/mediaremote-adapter>.
- Used for: Now Playing information and media controls (embedded as `MediaRemoteAdapter.framework`).
  It talks to Apple's private `MediaRemote.framework`.
- License: BSD 3-Clause. The fork has no LICENSE file; its source headers say
  "Copyright (c) 2025 Jonas van den Berg — This file is licensed under the BSD 3-Clause License",
  and the upstream repository's license is reproduced below.
- `MediaRemote.h`: the upstream package contains `Sources/CIMediaRemote/include/MediaRemote.h`, a
  header marked "Copyright (c) 2013-2014 Cykey (David Murray). All rights reserved." with no
  license grant. It declares the private framework's interface for the package's `CIMediaRemote`
  target. The header is present only in the upstream package (SwiftPM fetches it at build time);
  it is **not contained in or redistributed by this repository**, and no code here includes it.
  Its declarations are compiled into `MediaRemoteAdapter.framework`, so keep it in mind before
  distributing a built app.

```text
BSD 3-Clause License

Copyright (c) 2025, Jonas van den Berg and contributors

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## Web services

These services are called at run time; none of their code or data is bundled.

| Service | Used by | Terms |
|---|---|---|
| [Open-Meteo](https://open-meteo.com/) (`api.open-meteo.com`, `geocoding-api.open-meteo.com`) | Weather widget (forecast, city search) | Data under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/); attribution required (the app shows "Weather data by Open-Meteo.com" in the Weather settings). The free API is for **non-commercial use** only; commercial use needs an API subscription. |
| [Frankfurter](https://www.frankfurter.app/) (`api.frankfurter.app`) | Calculator widget (currency conversion) | Free, open-source API serving European Central Bank reference rates. |
| [ipify](https://www.ipify.org/) (`api.ipify.org`) | Network widget (public IP address, optional) | Free public API. |

## Apple frameworks and SF Symbols

The app uses Apple's system frameworks (SwiftUI, AppKit, IOKit, EventKit, CoreBluetooth,
AVFoundation, ScreenCaptureKit, App Intents, …) and SF Symbols through the system APIs. They are
part of macOS and the Xcode SDK, are used under the Xcode and Apple SDK license agreements, and
need no notice here. SF Symbols are not redistributed as files.
