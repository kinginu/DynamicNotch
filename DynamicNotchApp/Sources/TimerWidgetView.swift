import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// Dependencies: NookTimersStore, TimerWidgetSettings, ArrayPosition, TimerEntry
import SwiftUI
import Observation

// MARK: - TimerWidgetView

// Layout:
//   @State var timersStore: NookTimersStore?
//   body: Group with emptyState vs timersList conditional
//   .padding(.all); paddingDependingOnArrPos; frame width from TimerWidgetSettings; .onAppear
//
// The width now comes from the nook grid (NookWidgetLayout). The store is the
//   app-lifetime NookTimersStore.shared so timers keep running while the notch is closed.
// timer pass (2026-10-20), modelled on the iOS timer (docs/ios-timer-reference.md):
//   - a timer alert rings → TimerAlertView (bell, label, Stop / Repeat), like the expanded
//     Dynamic Island alert;
//   - no timer (or "+") → TimerCreatorView (Control Center / Clock: wheels, recents, label, start);
//   - one timer → TimerCountdownView (the expanded Dynamic Island: big orange remaining time in a
//     ring, label, end time, ✕ / pause·resume / +);
//   - several timers → TimerRowView rows (Lock Screen Live Activities) and a "+" button.
struct TimerWidgetView: View {

    var store: NookTimersStore = .shared

    @State private var showCreator: Bool

    /// `store` nil = the shared store (a `.shared` default argument would be evaluated outside the
    /// main actor).
    init(store: NookTimersStore? = nil, showCreator: Bool = false) {
        self.store = store ?? .shared
        _showCreator = State(initialValue: showCreator)
    }

    private let spring = Animation.spring(response: 0.3, dampingFraction: 0.85)

    var body: some View {
        Group {
            if let alert = store.alertingEntries.last {
                TimerAlertView(entry: alert, store: store, others: store.alertingEntries.count - 1)
                    .transition(.opacity)
            } else if store.timers.isEmpty || showCreator {
                TimerCreatorView(
                    onStart: { seconds, label in
                        store.add(label: label, totalSeconds: seconds)
                        withAnimation(spring) { showCreator = false }
                    },
                    onCancel: store.timers.isEmpty ? nil : {
                        withAnimation(spring) { showCreator = false }
                    },
                    store: store
                )
                .frame(maxHeight: .infinity)
                .transition(.opacity)
            } else if store.timers.count == 1, let entry = store.timers.first {
                TimerCountdownView(entry: entry, store: store, onNew: openCreator)
                    .transition(.opacity)
            } else {
                timersList(store)
                    .transition(.opacity)
            }
        }
        .animation(spring, value: store.alertingIDs)
        .nookWidgetFrame()
        .nookWidgetGalleryHook()
        .timerGalleryHook()
    }

    private func openCreator() {
        withAnimation(spring) { showCreator = true }
    }

    // MARK: - Timers List

    func timersList(_ store: NookTimersStore) -> some View {
        VStack(alignment: .leading, spacing: NookWidgetMetrics.stackSpacing) {
            HStack {
                Text("Timers")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                TimerRoundButton(systemImage: "plus", label: Text("New Timer"), diameter: 22, action: openCreator)
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(store.timers, id: \.id) { entry in
                        TimerRowView(entry: entry, store: store)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

// MARK: - Single timer (expanded Dynamic Island)

/// One timer: a large orange countdown inside a progress ring with the label and the
/// end time (Clock app), and round ✕ / pause·resume / + controls (Dynamic Island expanded view).
struct TimerCountdownView: View {
    var entry: TimerEntry
    var store: NookTimersStore
    var onNew: () -> Void

    @StoredSetting(.timerWidgetSettings) private var settings

    private var isExpired: Bool { entry.hasEnded }
    private var isRunning: Bool { entry.isRunning }

    private var progress: Double {
        guard entry.totalSeconds > 0 else { return 0 }
        return Double(max(0, entry.remainingSeconds)) / Double(entry.totalSeconds)
    }

    var body: some View {
        VStack(spacing: NookWidgetMetrics.spacing) {
            ZStack {
                TimerProgressRing(progress: isExpired ? 1 : progress, lineWidth: 5)
                VStack(spacing: 1) {
                    Text(entry.displayLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if isExpired {
                        Text("Done")
                            .font(.system(.title2, design: .rounded).weight(.semibold))
                            .foregroundStyle(TimerInsets.tint)
                    } else {
                        Text(TimerRowView.countdownText(remaining: entry.remainingSeconds,
                                                        showSeconds: settings.showSeconds))
                            .font(.system(.title, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(TimerInsets.tint.opacity(isRunning ? 1 : 0.6))
                            .contentTransition(.numericText(countsDown: true))
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                    }
                    endTime
                }
                .padding(.horizontal, 12)
            }
            .frame(width: 112, height: 112)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(entry.displayLabel))
            .accessibilityValue(isExpired ? Text("Done")
                                : Text(Duration.seconds(max(0, entry.remainingSeconds)).formatted(.units(width: .wide))))

            HStack(spacing: 14) {
                if isExpired {
                    TimerRoundButton(systemImage: "arrow.clockwise", label: Text("Repeat"), diameter: 30) {
                        store.repeatTimer(entry)
                    }
                    TimerRoundButton(systemImage: "stop.fill", label: Text("Stop"), diameter: 38, tint: TimerInsets.tint) {
                        store.stop(entry)
                    }
                } else {
                    TimerRoundButton(systemImage: "xmark", label: Text("Cancel"), diameter: 30) {
                        store.cancel(entry)
                    }
                    TimerRoundButton(systemImage: isRunning ? "pause.fill" : "play.fill",
                                     label: isRunning ? Text("Pause") : Text("Resume"),
                                     diameter: 38, tint: isRunning ? TimerInsets.tint : .green) {
                        isRunning ? store.pause(entry) : store.start(entry)
                    }
                }
                TimerRoundButton(systemImage: "plus", label: Text("New Timer"), diameter: 30, action: onNew)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// "🔔 3:45 PM" while running (the Clock app's end time); dimmed while paused.
    @ViewBuilder private var endTime: some View {
        if isRunning, let expiresAt = entry.expiresAt {
            Label {
                Text(expiresAt, format: .dateTime.hour().minute())
            } icon: {
                Image(systemName: "bell.fill")
            }
            .labelStyle(.titleAndIcon)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
        } else if entry.isPaused {
            Text("Paused")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Alert (a timer ended)

/// The ringing timer (the iOS timer alert): bell, label, "Timer Ended", and the
/// Stop / Repeat buttons. Stop silences the sound and removes the timer (it stays in Recents).
struct TimerAlertView: View {
    var entry: TimerEntry
    var store: NookTimersStore
    /// Further ringing timers behind this one.
    var others: Int = 0

    var body: some View {
        VStack(spacing: NookWidgetMetrics.spacing) {
            Spacer(minLength: 0)
            NookAlertBell(tint: TimerInsets.tint, diameter: 60)
            VStack(spacing: 1) {
                Text(entry.displayLabel)
                    .font(.headline)
                    .lineLimit(1)
                (others > 0 ? Text("Timer Ended (+\(others))") : Text("Timer Ended"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                TimerRoundButton(systemImage: "arrow.clockwise", label: Text("Repeat"), diameter: 30) {
                    store.repeatTimer(entry)
                }
                TimerCapsuleButton(title: Text("Stop"), systemImage: "stop.fill", prominent: true) {
                    store.stop(entry)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - DEBUG gallery

extension View {
    /// DEBUG: installs the timer gallery listener when the Timer widget first appears.
    func timerGalleryHook() -> some View {
        #if DEBUG
        return onAppear { TimerGalleryDebug.install() }
        #else
        return self
        #endif
    }
}

#if DEBUG
/// DEBUG-only snapshots of the timer states (timer pass). Same distributed notification as
/// DebugHooks (`DebugHooks.notificationName`); command `timergallery:<dir>` writes
/// `<dir>/timer-<state>-<dark|light>.png` for the widget (creator, single running, paused, list,
/// alert) and `<dir>/timer-notch-<compact|paused|minimal|alert>.png` for the closed-notch live
/// activity. Uses ephemeral stores (nothing is persisted, no timers tick, no sound). The listener is
/// installed when the Timer widget first appears, so open the Nook once first.
@MainActor
enum TimerGalleryDebug {
    private static var observer: NSObjectProtocol?

    static func install() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: DebugHooks.notificationName, object: nil, queue: .main
        ) { note in
            guard let command = note.object as? String, command.hasPrefix("timergallery:") else { return }
            let dir = String(command.dropFirst("timergallery:".count))
            MainActor.assumeIsolated { render(to: URL(fileURLWithPath: dir)) }
        }
        NSLog("[TimerGallery] installed")
    }

    private static func store(_ entries: [(label: String, total: Int, remaining: Int, state: TimerEntry.State)],
                              alerting: Bool = false) -> NookTimersStore {
        let store = NookTimersStore(persistent: false)
        store.debugSeed(entries, alerting: alerting)
        return store
    }

    static func render(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let previousGlass = NookGlass.forceFallback
        NookGlass.forceFallback = true
        defer { NookGlass.forceFallback = previousGlass }

        let width = NookWidgetLayout.width(of: .timer)
        let states: [(String, NookTimersStore, Bool)] = [
            ("creator", store([]), false),
            ("running", store([("Pasta", 600, 437, .running)]), false),
            ("paused", store([("", 300, 129, .idle)]), false),
            ("list", store([("Tea", 240, 75, .running), ("", 1800, 1210, .running), ("Laundry", 3600, 3000, .idle)]), false),
            ("alert", store([("Tea", 240, 0, .cancelled)], alerting: true), false),
        ]
        for (name, s, _) in states {
            for dark in [true, false] {
                let view = TimerWidgetView(store: s, showCreator: name == "creator")
                    .frame(width: width, height: WidgetGalleryDebug.rowHeight)
                    .clipped()
                    .padding(12)
                    .background(dark ? Color.black : Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, dark ? .dark : .light)
                NookWidgetSnapshot.writePNG(view, dark: dark, size: CGSize(width: width + 24, height: WidgetGalleryDebug.rowHeight + 24),
                                            to: dir.appendingPathComponent("timer-\(name)-\(dark ? "dark" : "light").png"), tag: "[TimerGallery]")
            }
        }

        // closed notch (Dynamic Island compact / minimal / alert), 200 × 32 pt camera housing
        let notch = CGSize(width: 200, height: 32)
        let notchStates: [(String, NookTimersStore, Bool)] = [
            ("compact", store([("", 300, 263, .running)]), false),
            ("compact-hours", store([("", 7200, 4521, .running)]), false),
            ("paused", store([("", 300, 129, .idle)]), false),
            ("minimal", store([("", 300, 263, .running)]), true),
            ("alert", store([("Tea", 240, 0, .cancelled)], alerting: true), false),
        ]
        for (name, s, minimal) in notchStates {
            let side: CGFloat
            if minimal {
                side = notch.height + 8
            } else if !s.alertingIDs.isEmpty {
                side = TimerInsets.alertSideWidth
            } else {
                side = TimerInsets.compactSideWidth(notchHeight: notch.height,
                                                    showsHours: (s.islandEntry?.remainingSeconds ?? 0) >= 3600)
            }
            let extra = minimal ? TimerInsets.minimalExtraWidth : 0
            let row = HStack(spacing: 0) {
                Group {
                    if minimal {
                        Image(systemName: "music.note").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    } else {
                        TimerLiveActivityView(side: .leading, store: s)
                    }
                }
                .padding(.leading, ClosedNotchActivityLayout.outerInset)
                .padding(.trailing, 4)
                .frame(width: side, height: notch.height, alignment: .leading)
                RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06))
                    .frame(width: notch.width, height: notch.height - 8)
                Group {
                    if minimal {
                        Image(systemName: "waveform").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    } else {
                        TimerLiveActivityView(side: .trailing, store: s)
                    }
                }
                .padding(.trailing, ClosedNotchActivityLayout.outerInset)
                .padding(.leading, 4)
                .frame(width: side, height: notch.height, alignment: .trailing)
                if minimal {
                    TimerMinimalView(store: s)
                        .padding(.trailing, ClosedNotchActivityLayout.outerInset - 4)
                        .frame(width: extra, height: notch.height, alignment: .trailing)
                }
            }
            .padding(.leading, extra)
            .padding(.vertical, 4)
            .background(UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12).fill(Color.black))
            .padding(12)
            .background(Color(white: 0.35))
            .environment(\.colorScheme, .dark)
            let w = notch.width + 2 * (side + extra) + 24
            NookWidgetSnapshot.writePNG(row, dark: true, size: CGSize(width: w, height: notch.height + 8 + 24),
                                        to: dir.appendingPathComponent("timer-notch-\(name).png"), tag: "[TimerGallery]")
        }
    }
}
#endif
