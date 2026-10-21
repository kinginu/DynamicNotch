import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// Previous / play-pause / next buttons on MediaManager
// restyle (2026-10-20): SF Symbols backward.fill / play.fill·pause.fill / forward.fill,
//   hierarchical primary style, a round hover highlight like Control Center's Now Playing, and
//   accessibility labels. Used by the Nook Media widget and the mini player.
struct MediaControlsView: View {
    private var mediaManager = MediaManager.shared

    var body: some View {
        let hasTrack = mediaManager.track != Track.empty
        HStack(spacing: 20) {
            ControlButton(systemName: "backward.fill", size: 15, label: Text("Previous Track")) {
                mediaManager.goToPreviousTrack()
            }
            ControlButton(systemName: mediaManager.isPlaying ? "pause.fill" : "play.fill", size: 22,
                          label: mediaManager.isPlaying ? Text("Pause") : Text("Play")) {
                mediaManager.togglePlayPause()
            }
            .contentTransition(.symbolEffect(.replace))
            ControlButton(systemName: "forward.fill", size: 15, label: Text("Next Track")) {
                mediaManager.goToNextTrack()
            }
        }
        .disabled(!hasTrack)
        .opacity(hasTrack ? 1 : 0.4)
        .foregroundStyle(.primary)
    }

    private struct ControlButton: View {
        let systemName: String
        let size: CGFloat
        let label: Text
        let action: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                Image(systemName: systemName)
                    .font(.system(size: size, weight: .semibold))
                    .frame(width: size + 18, height: size + 14)
                    .background(Circle().fill(.primary.opacity(hovering ? 0.12 : 0)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(ShrinkOnClick(minSize: 0.85))
            .onHover { hovering = $0 }
            .accessibilityLabel(label)
            .help(label)
        }
    }
}
