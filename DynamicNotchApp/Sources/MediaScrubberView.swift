import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// Observes MediaManager._duration. If >0: TimelineView(.periodic)
// VStack(Slider(tinted AnyShapeStyle) + HStack(Text.opacity + Spacer))
// scaleAndBlur transition. If duration <= 0: empty view
// the slider is drawn as a capsule bar that can be clicked or dragged to seek
//   (MediaManager.seek(to:) → mediaremote-adapter set_time).
// restyle (2026-10-20): macOS Now Playing-style scrubber — a 4 pt track
//   (quaternary) with a primary fill that grows to 8 pt while hovered or dragged, elapsed on the
//   left and remaining ("-m:ss") on the right in caption2 monospaced digits. Adjustable for
//   VoiceOver (±10 s).
struct MediaScrubberView: View {
    private var mediaManager: MediaManager = .shared
    @State private var dragFraction: Double? = nil
    @State private var hovering = false

    var body: some View {
        let duration = mediaManager.duration ?? 0  // duration is optional

        if duration > 0 {
            TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                let elapsed = dragFraction.map { $0 * duration } ?? min(max(mediaManager.currentElapsedTime, 0), duration)
                let expanded = hovering || dragFraction != nil
                VStack(spacing: 2) {
                    GeometryReader { geo in
                        let width = geo.size.width
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary)
                            Capsule().fill(.primary)
                                .frame(width: max(0, width * elapsed / duration))
                                .animation(dragFraction == nil ? .linear(duration: 1) : nil, value: elapsed)
                        }
                        .frame(height: expanded ? 8 : 4)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    dragFraction = min(max(value.location.x / max(width, 1), 0), 1)
                                }
                                .onEnded { value in
                                    let f = min(max(value.location.x / max(width, 1), 0), 1)
                                    mediaManager.seek(to: f * duration)
                                    dragFraction = nil
                                }
                        )
                        .animation(.smooth(duration: 0.15), value: expanded)
                    }
                    .frame(height: 12)
                    .onHover { hovering = $0 }

                    HStack {
                        Text(verbatim: formatTime(elapsed))  // elapsed on the left
                        Spacer()
                        Text(verbatim: "-" + formatTime(max(duration - elapsed, 0)))
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Playback Position"))
                .accessibilityValue(Text(verbatim: "\(formatTime(elapsed)) / \(formatTime(duration))"))
                .accessibilityAdjustableAction { direction in
                    let step: Double = direction == .increment ? 10 : -10
                    mediaManager.seek(to: min(max(elapsed + step, 0), duration))
                }
            }
            .transition(.scaleAndBlur)
        }
    }


    private func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60) }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
