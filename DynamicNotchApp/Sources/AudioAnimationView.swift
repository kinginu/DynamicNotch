import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

// Trailing side of the `.media` live activity: follows MediaManager (playing state, album-art
//   colour lightened by a 0.2 white blend, else nonShockingWhite), VolumeMonitor.volume and
//   MediaLiveActivitySettings (automatic colouring, effect). The "visualizer" effect is drawn as
//   animated bars (no audio tap is used), paused while playback is paused. "Custom GIF" plays the user-chosen GIF (equaliser bars when none is set); "None" shows nothing.
struct AudioAnimationView: View {
    private var mediaManager = MediaManager.shared
    @StoredSetting(.mediaLiveActivitySettings) private var settings

    var body: some View {
        Group {
            switch settings.effect {
            case .none:
                EmptyView()
            case .customGIF:
                GIFView(size: CGSize(width: 22, height: 22))
                    .frame(width: 22, height: 22)
                    .environment(\.mediaLiveActivitySettings, settings)
            case .visualizer, .albumArt:
                AudioBarsView(isPlaying: mediaManager.isPlaying, color: tint)
                    .frame(width: 20, height: 14)
            }
        }
        .animation(.spring(), value: mediaManager.isPlaying)  // spring animation
    }

    // album-art colour lightened by 0.2, else nonShockingWhite
    private var tint: Color {
        if settings.isAutomaticallyColored, let c = mediaManager.albumArtAverageColor {
            return Color(nsColor: c.lighter(amount: 0.2))
        }
        return .nonShockingWhite
    }
}

/// four bars driven by a low-rate TimelineView (≈7 fps, paused when not playing).
struct AudioBarsView: View {
    let isPlaying: Bool
    let color: Color

    private static let speeds: [Double] = [5.1, 3.7, 6.3, 4.4]
    private static let offsets: [Double] = [0, 1.3, 2.1, 0.7]

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.14, paused: !isPlaying)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    let level = isPlaying
                        ? 0.35 + 0.65 * abs(sin(t * Self.speeds[i] / 2 + Self.offsets[i]))
                        : 0.25
                    Capsule()
                        .fill(color)
                        .frame(width: 3)
                        .scaleEffect(x: 1, y: level, anchor: .center)
                        .animation(.easeInOut(duration: 0.14), value: level)
                }
            }
        }
    }
}
