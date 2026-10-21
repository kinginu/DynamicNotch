import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import AppKit
import Foundation
import SwiftUI

// View shown when no media apps are available.
//   getInstalledMediaApps iterates 14 known bundle identifiers,
//   checks each via NSWorkspace.URLForApplicationWithBundleIdentifier,
//   and builds [SystemAppMeta] for installed ones.
struct NoMediaAppsView: View {

    @State private var apps: [SystemAppMeta] = []

    // "nothing playing" state of the media widget: a hint plus launch buttons for
    //   the installed media apps.
    // restyle (2026-10-20): artwork-sized placeholder tile (music.note on a
    //   quaternary fill, like an empty Now Playing), "Not Playing", and up to four app icons.
    var body: some View {
        VStack(spacing: NookWidgetMetrics.spacing) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: NookWidgetMetrics.cornerRadius, style: .continuous)
                        .fill(.quaternary)
                    Image(systemName: "music.note")
                        .font(.title2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Not Playing")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if !apps.isEmpty {
                        Text("Open a music app")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !apps.isEmpty {
                HStack(spacing: 12) {
                    ForEach(apps.prefix(4), id: \.bundleId) { app in
                        Button { app.openApp() } label: {
                            if let icon = app.icon {
                                Image(nsImage: icon).resizable().scaledToFit().frame(width: 32, height: 32)
                            } else {
                                Image(systemName: "app").font(.title2).frame(width: 32, height: 32)
                            }
                        }
                        .buttonStyle(ShrinkOnClick(minSize: 0.85))
                        .help(app.name)
                        .accessibilityLabel(Text(verbatim: app.name))
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { if apps.isEmpty { apps = getInstalledMediaApps() } }
    }

    //   Iterates 14 known media app bundle identifiers:
    //   com.apple.Music, com.spotify.client, etc.
    //   For each, checks NSWorkspace.shared.URLForApplicationWithBundleIdentifier.
    //   If URL exists, creates SystemAppMeta(bundleId:) and appends.
    func getInstalledMediaApps() -> [SystemAppMeta] {
        let knownBundleIds = [
            "com.apple.Music",
            "com.spotify.client",
            "com.apple.TV",
            "com.apple.iTunes",
            "com.ableton.live",
            "com.adobe.adobe-media-player",
            "com.electron.music-player",
            "com.plexapp.plex",
            "com.vox.mac",
            "com.rogueamoeba.Airfoil",
            "com.rogueamoeba.AirfoilSatellite",
            "com.bitcart.Swinsian",
            "com.deezer.Deezer",
            "com.tidal.Tidal",
        ]

        let workspace = NSWorkspace.shared
        var installed: [SystemAppMeta] = []

        for bundleId in knownBundleIds {
            guard let url = workspace.urlForApplication(withBundleIdentifier: bundleId) else {
                continue
            }

            if FileManager.default.fileExists(atPath: url.path) {
                installed.append(SystemAppMeta(bundleId: bundleId))
            }
        }

        return installed
    }
}
