import SwiftUI

/// One side of the timer's closed-notch live activity, after the iOS Dynamic Island timer
/// (docs/ios-timer-reference.md):
///   - compact (a timer counts or is paused): leading = orange progress ring around `timer`
///     (`pause.fill` when paused), trailing = the remaining time in orange rounded digits;
///   - alert (a timer ended, NookTimersStore rings): leading = ringing bell + label, trailing = an
///     orange "Stop" capsule button (hover does not open the notch while the alert rings).
struct TimerLiveActivityView: View {
    var side: LiveActivityView.ActivitySide
    var store: NookTimersStore
    var fallbackLabel: String? = nil

    @StoredSetting(.timerWidgetSettings) private var settings

    /// Side width (`LiveActivityDescriptor.sideWidth`): the alert, or the compact countdown with
    /// room for an hours field while one hour or more remains.
    static func sideWidth(notchHeight: CGFloat) -> CGFloat {
        let store = NookTimersStore.shared
        if !store.alertingIDs.isEmpty { return TimerInsets.alertSideWidth }
        return TimerInsets.compactSideWidth(notchHeight: notchHeight,
                                            showsHours: (store.islandEntry?.remainingSeconds ?? 0) >= 3600)
    }

    var body: some View {
        if let alert = store.alertingEntries.last {
            alertContent(alert)
        } else if let entry = store.islandEntry {
            compactContent(entry)
        } else {
            // forced by a DEBUG hook or between two store updates
            Image(systemName: side == .leading ? "timer" : "bell.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(TimerInsets.tint)
        }
    }

    @ViewBuilder
    private func compactContent(_ entry: TimerEntry) -> some View {
        switch side {
        case .leading:
            ZStack {
                TimerProgressRing(progress: Double(max(0, entry.remainingSeconds)) / Double(max(1, entry.totalSeconds)),
                                  lineWidth: TimerInsets.closedRingLineWidth)
                Image(systemName: entry.isPaused ? "pause.fill" : "timer")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(TimerInsets.tint)
            }
            .frame(width: 20, height: 20)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(entry.displayLabel))
        case .trailing:
            Text(verbatim: TimerRowView.countdownText(remaining: entry.remainingSeconds, showSeconds: settings.showSeconds))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(TimerInsets.tint.opacity(entry.isPaused ? 0.55 : 1))
                .contentTransition(.numericText(countsDown: true))
                .lineLimit(1)
                .fixedSize()
                .accessibilityLabel(entry.isPaused ? Text("Paused") : Text("Time Remaining"))
                .accessibilityValue(Text(Duration.seconds(max(0, entry.remainingSeconds)).formatted(.units(width: .wide))))
        }
    }

    @ViewBuilder
    private func alertContent(_ entry: TimerEntry) -> some View {
        switch side {
        case .leading:
            HStack(spacing: 5) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TimerInsets.tint)
                    .symbolEffect(.wiggle, options: .repeating)
                Text(verbatim: entry.label.isEmpty ? (fallbackLabel ?? String(localized: "Timer")) : entry.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Timer Ended"))
        case .trailing:
            Button { store.stopAllAlerts() } label: {
                HStack(spacing: 3) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 8, weight: .bold))
                    Text("Stop")
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .frame(height: 20)
                .background(Capsule().fill(TimerInsets.tint))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityLabel(Text("Stop"))
        }
    }
}

/// Dynamic Island "minimal": the timer's ring shown beside another activity.
struct TimerMinimalView: View {
    var store: NookTimersStore

    var body: some View {
        if let entry = store.islandEntry {
            ZStack {
                TimerProgressRing(progress: Double(max(0, entry.remainingSeconds)) / Double(max(1, entry.totalSeconds)),
                                  lineWidth: 2)
                if entry.isPaused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(TimerInsets.tint)
                }
            }
            .frame(width: TimerInsets.minimalDiameter, height: TimerInsets.minimalDiameter)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(entry.displayLabel))
            .accessibilityValue(Text(Duration.seconds(max(0, entry.remainingSeconds)).formatted(.units(width: .wide))))
        }
    }
}
