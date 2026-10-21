import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
//   VStack(leading, spacing 8) { HStack { Button(AlbumCover…, ShrinkOnClick), VStack { Group { title, artist } }, MediaControls },
//   NowPlayingSourceSwitcher, MediaScrubber } .animation(.bouncySmooth, value: concatenatedTrackId) .foregroundColor(nonShockingWhite)
// laid out for the 250 pt "Media Player" widget: artwork (tap = open the player app)
//   with the app's icon as a badge, marquee title/artist, the source switcher, the scrubber, then the
//   transport controls on their own row (they did not fit beside the text at this width).

// Equatable / View conformances
struct MediaPlayerView: Equatable, View {

    private var mediaManager = MediaManager.shared  // MediaManager.shared singleton access

    @Namespace private var namespace  // matchedGeometryEffect namespace

    // restyle (2026-10-20, Apple-native look): 64 pt artwork with
    //   continuous 12 pt corners and the player app's icon as a badge; title (headline) and artist
    //   (subheadline, secondary) on two lines; scrubber with elapsed / remaining; transport controls
    //   (SF Symbols backward.fill / play.fill·pause.fill / forward.fill) centred below.
    var body: some View {
        let track = mediaManager.track
        VStack(alignment: .leading, spacing: NookWidgetMetrics.spacing) {  // alignment
            HStack(alignment: .center, spacing: 12) {
                // Button wrapping AlbumCoverView with ShrinkOnClick
                Button { mediaManager.openApp() } label: {
                    artwork(track)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: NookWidgetMetrics.cornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: NookWidgetMetrics.cornerRadius, style: .continuous)
                                .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
                        .matchedGeometryEffect(id: "albumCover", in: namespace)
                        .overlay(alignment: .bottomTrailing) {
                            if let icon = appIcon(track) {
                                Image(nsImage: icon)
                                    .resizable()
                                    .scaledToFit()
                                    .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
                                    .frame(width: 20, height: 20)
                                    .offset(x: 5, y: 5)
                            }
                        }
                }
                .buttonStyle(ShrinkOnClick())
                .help(track.appName)
                .accessibilityLabel(Text(verbatim: track.appName.isEmpty ? track.title : track.appName))
                .accessibilityHint(Text("Open the player app"))

                VStack(alignment: .leading, spacing: 2) {
                    Group {
                        TheMarquee(text: track.title, font: .headline)
                            .foregroundStyle(.primary)
                        TheMarquee(text: track.artist.isEmpty ? track.album : track.artist,
                                   font: .subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .allowsHitTesting(false)
                    NowPlayingSourceSwitcherView()  // position 1
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }

            MediaScrubberView()  // position 2

            MediaControlsView()
                .frame(maxWidth: .infinity)
        }
        .animation(.bouncySmooth, value: concatenatedTrackId)
    }

    @ViewBuilder
    private func artwork(_ track: Track) -> some View {
        if let art = track.albumArtImage {
            Image(nsImage: art)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Rectangle().fill(.quaternary)
                Image(systemName: "music.note")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func appIcon(_ track: Track) -> NSImage? {
        guard !track.bundleIdentifier.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: track.bundleIdentifier) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    // views hold only singletons/namespace; treat all instances as equal
    static func == (lhs: Self, rhs: Self) -> Bool { true }

    private var concatenatedTrackId: String {
        let track = mediaManager.track
        return track.id + track.metaId + String(describing: track.isPlaying) + track.albumId + track.title
    }
}
