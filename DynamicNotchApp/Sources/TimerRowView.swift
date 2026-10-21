import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
import SwiftUI
import Observation

// Layout: HStack(center, spacing: 6) { Image; VStack { Text(countdown); Button if expired } }
//   background RoundedRectangle(cornerRadius: 8, continuous) — red 0.2 when expired, white 0.12 otherwise
// adds pause/resume and cancel/dismiss controls (NookTimersStore API) and a
//   progress ring; `state == .cancelled` is what NookTimersStore.tick sets when a timer ends.
// timer pass (2026-10-20, iOS Clock / Dynamic Island, docs/ios-timer-reference.md):
//   one row of the multiple-timers list, like a Lock Screen timer Live Activity — orange progress
//   ring, orange remaining time (dimmed when paused), label, an orange pause / green resume button
//   and a grey ✕. An ended timer shows "Done" with Stop (and Repeat while it rings).
struct TimerRowView: View {
    // the timer this row displays (TimerWidgetView passes `entry:`)
    var entry: TimerEntry
    var store: NookTimersStore = .shared

    @StoredSetting(.timerWidgetSettings) private var settings

    private var isExpired: Bool { entry.hasEnded }
    private var isRunning: Bool { entry.isRunning }

    // Digital: "%d:%02d" (< 1 h) / "%d:%02d:%02d"; text: "Xh Ym" / "Ym"
    var countdownText: String {
        Self.countdownText(remaining: entry.remainingSeconds, showSeconds: settings.showSeconds)
    }

    static func countdownText(remaining rawRemaining: Int, showSeconds: Bool) -> String {
        let remaining = max(0, rawRemaining)
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        let seconds = remaining % 60
        if !showSeconds {
            return hours > 0 ? "\(hours)h \(minutes)m" : "\(max(minutes, remaining > 0 ? 1 : 0))m"
        }
        if remaining < 3600 {
            return String(format: "%d:%02d", minutes, seconds)
        }
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }

    /// Short duration for chips and menus: "5m", "1h30m", "45s", "2m30s".
    static func shortDuration(_ total: Int) -> String {
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h)h") }
        if m > 0 { parts.append("\(m)m") }
        if s > 0 || parts.isEmpty { parts.append("\(s)s") }
        return parts.joined()
    }

    private var progress: Double {
        guard entry.totalSeconds > 0 else { return 0 }
        return Double(max(0, entry.remainingSeconds)) / Double(entry.totalSeconds)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            ZStack {
                TimerProgressRing(progress: isExpired ? 1 : progress, lineWidth: 3)
                Image(systemName: isExpired ? "bell.fill" : (isRunning ? "timer" : "pause.fill"))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(TimerInsets.tint)
            }
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text(isExpired ? String(localized: "Done") : countdownText)
                    .font(.system(.headline, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(TimerInsets.tint.opacity(isRunning || isExpired ? 1 : 0.6))
                    .contentTransition(.numericText(countsDown: true))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(entry.displayLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 2)

            if isExpired {
                TimerRoundButton(systemImage: "arrow.clockwise", label: Text("Repeat"), diameter: 22) {
                    store.repeatTimer(entry)
                }
                TimerRoundButton(systemImage: "stop.fill", label: Text("Stop"), diameter: 22, tint: TimerInsets.tint) {
                    store.stop(entry)
                }
            } else {
                TimerRoundButton(systemImage: isRunning ? "pause.fill" : "play.fill",
                                 label: isRunning ? Text("Pause") : Text("Resume"),
                                 diameter: 22, tint: isRunning ? TimerInsets.tint : .green) {
                    isRunning ? store.pause(entry) : store.start(entry)
                }
                TimerRoundButton(systemImage: "xmark", label: Text("Cancel"), diameter: 22) {
                    store.cancel(entry)
                }
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: NookWidgetMetrics.rowCornerRadius, style: .continuous)  // real init labels
                .fill(isExpired ? AnyShapeStyle(TimerInsets.tint.opacity(0.2)) : AnyShapeStyle(.quinary))
        )
        .animation(.easeInOut, value: isExpired)
    }
}

// MARK: - Shared timer controls

/// Orange ring that empties as the timer runs (Dynamic Island / Clock style).
struct TimerProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat
    var tint: Color = TimerInsets.tint

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.linear(duration: 0.5), value: progress)
    }
}

/// Round icon button in the iOS timer colours: the glyph in `tint` on glass tinted with it (orange
/// pause, green start/resume), or a primary glyph on plain glass (✕, +). Material before macOS 26.
struct TimerRoundButton: View {
    var systemImage: String
    var label: Text
    var diameter: CGFloat = 26
    var tint: Color? = nil
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {

            // does not tint / hide it
            Color.clear
                .frame(width: diameter, height: diameter)
                .nookGlass(in: Circle(), tint: tint?.opacity(0.3), interactive: true)
                .overlay {
                    if #available(macOS 26, *), !NookGlass.forceFallback {
                        // glass responds to hover / press itself
                    } else {
                        Circle().fill(.primary.opacity(hovering ? 0.08 : 0))
                    }
                }
                .overlay {
                    Image(systemName: systemImage)
                        .font(.system(size: diameter * 0.4, weight: .semibold))
                        .foregroundStyle(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary))
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
        .help(label)
    }
}

/// Capsule text button (alert Stop / Repeat): filled with `tint` when prominent.
struct TimerCapsuleButton: View {
    var title: Text
    var systemImage: String
    var tint: Color = TimerInsets.tint
    var prominent: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Capsule().fill(.clear)
                .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30)
                .nookGlass(in: Capsule(), tint: prominent ? tint : nil, interactive: true)
                .overlay {
                    Label { title } icon: { Image(systemName: systemImage) }
                        .font(.subheadline.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(prominent ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
                        .padding(.horizontal, 12)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
