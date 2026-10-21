// Focus (Pomodoro) widget (2026-10-20): `NookWidget.pomodoro`, 4 grid cells (200 pt).
//
//   - session: phase chip (green Focus / blue Short·Long Break) and today's completed count, a
//     progress ring with the remaining time and the cycle's session dots, the optional task label,
//     and Reset / Start·Pause / Skip;
//   - end alert (PomodoroStore rings): bell, "Focus Done" / "Break Over", what comes next, and
//     Stop / Start Break·Start Focus.
// The closed-notch live activity (`LiveActivity.pomodoro`) is `PomodoroLiveActivityView`: the
// Timer's compact style (ring | remaining time) with the Focus symbol and green / blue tint.
// Reuses the Timer widget's TimerProgressRing / TimerRoundButton / TimerCapsuleButton and
// TimerRowView.countdownText (the Timer files are not modified).
import SwiftUI
import AppKit
import Observation

struct PomodoroWidgetView: View {
    var store: PomodoroStore = .shared

    private let spring = Animation.spring(response: 0.3, dampingFraction: 0.85)

    var body: some View {
        Group {
            if let ended = store.alertPhase {
                PomodoroAlertView(ended: ended, store: store)
                    .transition(.opacity)
            } else {
                PomodoroSessionView(store: store)
                    .transition(.opacity)
            }
        }
        .animation(spring, value: store.alertPhase)
        .nookWidgetFrame()
        .nookWidgetGalleryHook()
    }
}

// MARK: - Session

struct PomodoroSessionView: View {
    @Bindable var store: PomodoroStore

    private var tint: Color { store.phase.tint }

    var body: some View {
        VStack(spacing: 6) {
            header
            ring
            TextField("What are you working on?", text: $store.taskLabel)
                .textFieldStyle(.plain)
                .font(.callout)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: NookWidgetMetrics.controlHeight)
                .background(Capsule().fill(.quinary))
                .accessibilityLabel(Text("Task"))
            controls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 4) {
            Label {
                Text(verbatim: store.phase.title)
            } icon: {
                Image(systemName: store.phase.symbol)
            }
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Label {
                Text(verbatim: "\(store.completedToday)")
                    .monospacedDigit()
            } icon: {
                Image(systemName: "checkmark.circle.fill")
            }
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .help(Text("Focus sessions completed today"))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Completed today"))
            .accessibilityValue(Text(verbatim: "\(store.completedToday)"))
        }
        .frame(height: 18)
    }

    private var ring: some View {
        ZStack {
            TimerProgressRing(progress: store.progress, lineWidth: 5, tint: tint)
            VStack(spacing: 4) {
                Text(TimerRowView.countdownText(remaining: store.remainingSeconds, showSeconds: true))
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint.opacity(store.isRunning ? 1 : 0.65))
                    .contentTransition(.numericText(countsDown: true))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                PomodoroSessionDots(store: store)
                if store.isPaused {
                    Text("Paused")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
        }
        .frame(width: 92, height: 92)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: store.phase.title))
        .accessibilityValue(Text(Duration.seconds(max(0, store.remainingSeconds)).formatted(.units(width: .wide))))
    }

    private var controls: some View {
        HStack(spacing: 14) {
            TimerRoundButton(systemImage: "arrow.counterclockwise", label: Text("Reset"), diameter: 28) {
                store.reset()
            }
            TimerRoundButton(systemImage: store.isRunning ? "pause.fill" : "play.fill",
                             label: store.isRunning ? Text("Pause")
                                 : (store.isPaused ? Text("Resume") : Text("Start")),
                             diameter: 36, tint: tint) {
                store.toggle()
            }
            TimerRoundButton(systemImage: "forward.end.fill", label: Text("Skip"), diameter: 28) {
                store.skip()
            }
        }
    }
}

/// One dot per focus session of the cycle: filled = completed, ringed = the current focus session.
struct PomodoroSessionDots: View {
    var store: PomodoroStore

    var body: some View {
        let total = store.longBreakEvery
        let done = min(store.completedInCycle, total)
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .fill(i < done ? AnyShapeStyle(Color.green) : AnyShapeStyle(.quaternary))
                    .overlay {
                        if i == done, store.phase == .focus {
                            Circle().stroke(Color.green, lineWidth: 1)
                        }
                    }
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Session \(min(done + 1, total)) of \(total)"))
    }
}

// MARK: - End alert

struct PomodoroAlertView: View {
    var ended: PomodoroPhase
    var store: PomodoroStore

    private var next: PomodoroPhase { store.phase }

    var body: some View {
        VStack(spacing: NookWidgetMetrics.spacing) {
            Spacer(minLength: 0)
            NookAlertBell(tint: ended.tint, diameter: 56)
            VStack(spacing: 1) {
                (ended == .focus ? Text("Focus Done") : Text("Break Over"))
                    .font(.headline)
                    .lineLimit(1)
                Text("Next: \(next.title), \(TimerRowView.shortDuration(store.phaseSeconds))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if ended == .focus, !store.taskLabel.isEmpty {
                    Text(verbatim: store.taskLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                TimerRoundButton(systemImage: "stop.fill", label: Text("Stop"), diameter: 30) {
                    store.stopAlert()
                }
                TimerCapsuleButton(title: next.isBreak ? Text("Start Break") : Text("Start Focus"),
                                   systemImage: "play.fill", tint: next.tint, prominent: true) {
                    store.startNext()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Closed notch (Dynamic Island compact / alert)

enum PomodoroInsets {
    /// Side width of the closed-notch activity (same metrics as the timer's).
    static func sideWidth(notchHeight: CGFloat, store: PomodoroStore = .shared) -> CGFloat {
        if store.isAlerting { return TimerInsets.alertSideWidth }
        return TimerInsets.compactSideWidth(notchHeight: notchHeight, showsHours: store.remainingSeconds >= 3600)
    }
}

/// One side of the `.pomodoro` live activity:
///   - compact: leading = green (focus) / blue (break) progress ring around the phase symbol
///     (`pause.fill` when paused), trailing = the remaining time in the same tint;
///   - alert: leading = ringing bell + "Focus Done" / "Break Over", trailing = the next phase's
///     symbol and length. Display only — open the notch to Stop / start the next phase.
struct PomodoroLiveActivityView: View {
    var side: LiveActivityView.ActivitySide
    var store: PomodoroStore

    var body: some View {
        if let ended = store.alertPhase {
            alertContent(ended)
        } else {
            compactContent
        }
    }

    @ViewBuilder private var compactContent: some View {
        let tint = store.phase.tint
        switch side {
        case .leading:
            ZStack {
                TimerProgressRing(progress: store.progress, lineWidth: TimerInsets.closedRingLineWidth, tint: tint)
                Image(systemName: store.isPaused ? "pause.fill" : store.phase.symbol)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 20, height: 20)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: store.phase.title))
        case .trailing:
            Text(verbatim: TimerRowView.countdownText(remaining: store.remainingSeconds, showSeconds: true))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint.opacity(store.isPaused ? 0.55 : 1))
                .contentTransition(.numericText(countsDown: true))
                .lineLimit(1)
                .fixedSize()
                .accessibilityLabel(store.isPaused ? Text("Paused") : Text("Time Remaining"))
                .accessibilityValue(Text(Duration.seconds(max(0, store.remainingSeconds)).formatted(.units(width: .wide))))
        }
    }

    @ViewBuilder private func alertContent(_ ended: PomodoroPhase) -> some View {
        switch side {
        case .leading:
            HStack(spacing: 5) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ended.tint)
                    .symbolEffect(.wiggle, options: .repeating)
                (ended == .focus ? Text("Focus Done") : Text("Break Over"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .accessibilityElement(children: .combine)
        case .trailing:
            HStack(spacing: 4) {
                Image(systemName: store.phase.symbol)
                    .font(.system(size: 10, weight: .semibold))
                Text(verbatim: TimerRowView.shortDuration(store.phaseSeconds))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .foregroundStyle(store.phase.tint)
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Next: \(store.phase.title), \(TimerRowView.shortDuration(store.phaseSeconds))"))
        }
    }
}

// MARK: - DEBUG gallery

#if DEBUG
/// DEBUG-only snapshots (same distributed notification as DebugHooks, `DebugHooks.notificationName`):
/// `pomodorogallery:<dir>` writes `<dir>/pomodoro-<state>-<dark|light>.png` (the widget at its grid
/// width × 202 pt: idle, running, paused-break, long-break, alert), `pomodoro-settings-<dark|light>.png`
/// (Settings ▸ Widgets ▸ Focus at 480 pt) and `pomodoro-notch-<compact|paused|break|alert>.png` (the
/// closed-notch activity in a 200 × 32 pt housing). Ephemeral stores: nothing ticks, rings or is
/// persisted. Installed by `PomodoroStore.start()` at launch (no need to open the Nook first).
@MainActor
enum PomodoroGalleryDebug {
    private static var observer: NSObjectProtocol?

    static func install() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: DebugHooks.notificationName, object: nil, queue: .main
        ) { note in
            guard let command = note.object as? String, command.hasPrefix("pomodorogallery:") else { return }
            let dir = String(command.dropFirst("pomodorogallery:".count))
            MainActor.assumeIsolated { render(to: URL(fileURLWithPath: dir)) }
        }
        NSLog("[PomodoroGallery] installed")
    }

    private static func store(_ phase: PomodoroPhase, _ status: PomodoroStore.Status, remaining: Int, total: Int,
                              completed: Int, today: Int, label: String = "",
                              alert: PomodoroPhase? = nil) -> PomodoroStore {
        let s = PomodoroStore(persistent: false)
        s.debugSeed(phase: phase, status: status, remaining: remaining, total: total,
                    completed: completed, today: today, label: label, alert: alert)
        return s
    }

    static func render(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let previousGlass = NookGlass.forceFallback
        NookGlass.forceFallback = true
        defer { NookGlass.forceFallback = previousGlass }

        let width = NookWidgetLayout.width(of: .pomodoro)
        let height = NookWidgetLayout.cellHeight
        let states: [(String, PomodoroStore)] = [
            ("idle", store(.focus, .idle, remaining: 1500, total: 1500, completed: 0, today: 0)),
            ("running", store(.focus, .running, remaining: 1093, total: 1500, completed: 2, today: 5, label: "Write report")),
            ("paused-break", store(.shortBreak, .paused, remaining: 187, total: 300, completed: 3, today: 6)),
            ("long-break", store(.longBreak, .running, remaining: 842, total: 900, completed: 4, today: 8)),
            ("alert", store(.shortBreak, .idle, remaining: 300, total: 300, completed: 1, today: 4,
                            label: "Write report", alert: .focus)),
        ]
        for (name, s) in states {
            for dark in [true, false] {
                let view = PomodoroWidgetView(store: s)
                    .frame(width: width, height: height)
                    .clipped()
                    .padding(12)
                    .background(dark ? Color.black : Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, dark ? .dark : .light)
                NookWidgetSnapshot.writePNG(view, dark: dark, size: CGSize(width: width + 24, height: height + 24),
                                            to: dir.appendingPathComponent("pomodoro-\(name)-\(dark ? "dark" : "light").png"), tag: "[PomodoroGallery]")
            }
        }

        for dark in [true, false] {
            let view = PomodoroWidgetSettingsView()
                .frame(width: 480, height: 520)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, dark ? .dark : .light)
            NookWidgetSnapshot.writePNG(view, dark: dark, size: CGSize(width: 480, height: 520),
                                        to: dir.appendingPathComponent("pomodoro-settings-\(dark ? "dark" : "light").png"), tag: "[PomodoroGallery]")
        }

        let notch = CGSize(width: 200, height: 32)
        let notchStates: [(String, PomodoroStore)] = [
            ("compact", store(.focus, .running, remaining: 1093, total: 1500, completed: 2, today: 5)),
            ("paused", store(.focus, .paused, remaining: 640, total: 1500, completed: 2, today: 5)),
            ("break", store(.shortBreak, .running, remaining: 187, total: 300, completed: 3, today: 6)),
            ("alert", store(.shortBreak, .idle, remaining: 300, total: 300, completed: 1, today: 4, alert: .focus)),
        ]
        for (name, s) in notchStates {
            let side = PomodoroInsets.sideWidth(notchHeight: notch.height, store: s)
            let row = HStack(spacing: 0) {
                PomodoroLiveActivityView(side: .leading, store: s)
                    .padding(.leading, ClosedNotchActivityLayout.outerInset)
                    .padding(.trailing, 4)
                    .frame(width: side, height: notch.height, alignment: .leading)
                RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06))
                    .frame(width: notch.width, height: notch.height - 8)
                PomodoroLiveActivityView(side: .trailing, store: s)
                    .padding(.trailing, ClosedNotchActivityLayout.outerInset)
                    .padding(.leading, 4)
                    .frame(width: side, height: notch.height, alignment: .trailing)
            }
            .padding(.vertical, 4)
            .background(UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12).fill(Color.black))
            .padding(12)
            .background(Color(white: 0.35))
            .environment(\.colorScheme, .dark)
            NookWidgetSnapshot.writePNG(row, dark: true, size: CGSize(width: notch.width + 2 * side + 24, height: notch.height + 8 + 24),
                                        to: dir.appendingPathComponent("pomodoro-notch-\(name).png"), tag: "[PomodoroGallery]")
        }
    }
}
#endif
