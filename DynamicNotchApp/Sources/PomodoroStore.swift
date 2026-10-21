// Focus (Pomodoro) widget state (2026-10-20).
//
// One app-lifetime session cycle: focus → short break → focus → … → long break every
// `longBreakEvery` completed focus sessions (PomodoroWidgetSettings; 25 / 5 / 15 min, every 4 by
// default). Start / pause / skip / reset, a session counter (focus sessions completed in the current
// cycle), today's completed count and an optional task label — all persisted in UserDefaults
// ("nook_pomodoro_state"), so a running session survives the notch closing and a relaunch.
//
// When a phase ends the store rings like the Timer widget (NookTimersStore): the Timer's "When Timer
// Ends" sound (or Stop Playing / None) repeats every 2.5 s until the alert is stopped, the next
// phase is started, or the Timer's "Alert Duration" passes. With "Start breaks / focus
// automatically" the next phase starts at once and the sound plays once (with Stop Playing, the
// music is paused instead).
//

// (removed, or absent at launch) the store is reset: a session nobody can see does not keep
// cycling, and an "Until Stopped" alert cannot ring with no way to silence it.
//
// The closed-notch live activity `.pomodoro` (LiveActivity.swift) is requested while a session
// runs or is paused (if `showInClosedNotch`) and while an end alert rings; LiveActivityCenter.start()
// calls `start()` once at launch.
//
// The session logic itself (start / pause / skip / reset / phase end / relaunch catch-up) is the pure
// state machine `PomodoroCycle` (PomodoroEngine.swift, documented and tested there); this store
// adds the clock, the 0.5 s tick, the alert, persistence and the live activity.
import Foundation
import AppKit
import Observation
import SwiftUI

extension PomodoroPhase {
    /// Green ring while focusing, blue during breaks.
    var tint: Color { isBreak ? .blue : .green }

    var symbol: String { isBreak ? "cup.and.saucer.fill" : "brain.head.profile" }
}

extension PomodoroWidgetSettings {
    /// The cycle configuration of these settings.
    var cycleConfig: PomodoroConfig {
        PomodoroConfig(focusSeconds: seconds(of: .focus), shortBreakSeconds: seconds(of: .shortBreak),
                       longBreakSeconds: seconds(of: .longBreak), longBreakEvery: longBreakEvery,
                       autoStartBreaks: autoStartBreaks, autoStartFocus: autoStartFocus)
    }
}

@Observable
final class PomodoroStore {
    typealias Status = PomodoroStatus

    static let shared = PomodoroStore()

    /// The session state (PomodoroEngine.swift).
    private(set) var cycle: PomodoroCycle

    var phase: PomodoroPhase { cycle.phase }
    var status: Status { cycle.status }
    /// Seconds left in the current phase (updated by the 0.5 s tick while running).
    var remainingSeconds: Int { cycle.remainingSeconds }
    /// Length of the current phase, fixed when the phase starts (the settings may change meanwhile).
    var phaseSeconds: Int { cycle.phaseSeconds }
    var expiresAt: Date? { cycle.expiresAt }
    /// Focus sessions completed in the current cycle (reset by a long break and by Reset).
    var completedInCycle: Int { cycle.completedInCycle }
    /// The phase that just ended while its end alert rings (nil = no alert).
    private(set) var alertPhase: PomodoroPhase? = nil
    /// Optional "what am I working on" label.
    var taskLabel: String = "" { didSet { if taskLabel != oldValue { save() } } }

    @ObservationIgnored private let persistent: Bool
    @ObservationIgnored private var tickTimer: Timer? = nil
    @ObservationIgnored private var ringTimer: Timer? = nil
    @ObservationIgnored private var alertDeadline: Date? = nil
    @ObservationIgnored private var started = false
    @ObservationIgnored private var settingsTask: Task<Void, Never>? = nil
    @ObservationIgnored private var nookTask: Task<Void, Never>? = nil

    private let key = "nook_pomodoro_state"
    static let ringInterval: TimeInterval = 2.5

    init(persistent: Bool = true) {
        self.persistent = persistent
        cycle = PomodoroCycle(config: SettingsStore[.pomodoroWidgetSettings].cycleConfig)
        if persistent { load() }
        if cycle.status == .running { startTick() }
    }

    deinit {
        tickTimer?.invalidate()
        ringTimer?.invalidate()
        settingsTask?.cancel()
        nookTask?.cancel()
    }

    private var settings: PomodoroWidgetSettings { SettingsStore[.pomodoroWidgetSettings] }
    private var config: PomodoroConfig { settings.cycleConfig }

    // MARK: - Derived

    var isRunning: Bool { cycle.isRunning }
    var isPaused: Bool { cycle.isPaused }
    var isAlerting: Bool { alertPhase != nil }
    /// Something to show in the closed notch (a session counts / is paused, or an alert rings).
    var hasIslandContent: Bool { isAlerting || status != .idle }

    /// Fraction of the current phase left (1 = full).
    var progress: Double { cycle.progress }

    /// Focus sessions completed today.
    var completedToday: Int { cycle.completedToday(now: Date(), calendar: .current) }

    var longBreakEvery: Int { config.cycleLength }

    /// The phase after the current one ends (a focus session ends in a long break when it completes
    /// the cycle).
    var nextPhase: PomodoroPhase { cycle.nextPhase(config) }

    // MARK: - Lifetime

    /// Called once at launch (LiveActivityCenter.start()): follows the settings and mirrors the state
    /// into the closed-notch live activity.
    @MainActor func start() {
        guard !started else { return }
        started = true
        settingsTask = Task { @MainActor [weak self] in
            for await _ in SettingsStore.updates(.pomodoroWidgetSettings, initial: false) {
                guard let self else { return }
                self.settingsChanged()
            }
        }
        // the widget (the only place with Stop / Start) left the Nook, or is absent at launch
        nookTask = Task { @MainActor [weak self] in
            for await nook in SettingsStore.updates(.nookSettings, initial: true) {
                guard let self else { return }
                if !nook.widgets.contains(.pomodoro), self.hasIslandContent || self.ringTimer != nil {
                    self.reset()
                }
            }
        }
        syncActivity()
        #if DEBUG
        PomodoroGalleryDebug.install()
        #endif
    }

    private func settingsChanged() {
        if status == .idle {
            cycle.configChanged(config)
            save()
        } else {
            syncActivity()
        }
    }

    // MARK: - Controls

    func toggle() { isRunning ? pause() : resume() }

    /// Start (idle) or resume (paused) the current phase.
    func resume() {
        stopAlert()
        guard cycle.resume(now: Date(), config: config) else { return }
        startTick()
        save()
    }

    func pause() {
        guard cycle.pause(now: Date()) else { return }
        stopTick()
        save()
    }

    /// End the current phase now without counting it and move to the next one (not started). A
    /// skipped focus session is not counted, so it is followed by a short break even when completing
    /// it would have earned the long break.
    func skip() {
        stopAlert()
        cycle.skip(config: config)
        stopTick()
        save()
    }

    /// Back to an idle focus session at the start of a new cycle (today's count is kept).
    func reset() {
        stopAlert()
        cycle.reset(config: config)
        stopTick()
        save()
    }

    /// Silence the end alert (the next phase stays ready to start).
    func stopAlert() {
        guard alertPhase != nil || ringTimer != nil else { return }
        alertPhase = nil
        stopRinging()
        save()
    }

    /// Alert action: start the phase that follows the one that ended.
    func startNext() {
        stopAlert()
        if status != .running { resume() }
    }

    // MARK: - Phases

    /// A phase reached its end (tick or relaunch catch-up): the cycle already moved on (and maybe
    /// auto-started the next phase); signal it.
    private func phaseEnded(_ end: PomodoroPhaseEnd) {
        stopTick()
        if cycle.isRunning { startTick() }
        save()
        guard end.rings else { return }
        if end.autoStarted {
            signalPhaseEnd()
        } else {
            beginAlert(end.ended)
        }
    }

    // MARK: - Tick

    private func startTick() {
        guard tickTimer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func stopTick() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func tick() {
        guard status == .running, expiresAt != nil else { stopTick(); return }
        var next = cycle
        let end = next.tick(now: Date(), config: config, calendar: .current)

        if next != cycle { cycle = next }
        if let end { phaseEnded(end) }
    }

    // MARK: - Alert (same sound settings as the Timer widget)

    private func beginAlert(_ ended: PomodoroPhase) {
        alertPhase = ended
        let timerSettings = SettingsStore[.timerWidgetSettings]
        alertDeadline = timerSettings.alertSeconds > 0
            ? Date().addingTimeInterval(TimeInterval(timerSettings.alertSeconds)) : nil
        signalPhaseEnd()
        save()
        guard ringTimer == nil else { return }
        let timer = Timer(timeInterval: Self.ringInterval, repeats: true) { [weak self] _ in self?.ring() }
        RunLoop.main.add(timer, forMode: .common)
        ringTimer = timer
    }

    private func ring() {
        guard alertPhase != nil else { stopRinging(); return }
        if let alertDeadline, Date() >= alertDeadline {
            stopAlert()
            return
        }
        playSound()
    }

    private func stopRinging() {
        ringTimer?.invalidate()
        ringTimer = nil
        alertDeadline = nil
    }

    /// The end-of-phase signal: the Timer's sound, or (Stop Playing) pausing the music.
    private func signalPhaseEnd() {
        if SettingsStore[.timerWidgetSettings].soundName == TimerWidgetSettings.stopPlayingSound {
            guard persistent else { return }
            // the store runs on the main thread (Timers on RunLoop.main, the UI); MediaManager is @MainActor
            MainActor.assumeIsolated {
                if MediaManager.shared.isPlaying { MediaManager.shared.togglePlayPause() }
            }
        } else {
            playSound()
        }
    }

    private func playSound() {
        guard persistent else { return }
        let name = SettingsStore[.timerWidgetSettings].soundName
        guard !name.isEmpty, name != TimerWidgetSettings.stopPlayingSound else { return }
        (NSSound(named: name) ?? NSSound(named: "Glass"))?.play()
    }

    // MARK: - Closed notch

    /// Request / remove the `.pomodoro` live activity.
    func syncActivity() {
        guard persistent else { return }
        let show = isAlerting || (status != .idle && settings.showInClosedNotch)
        if show {
            ActiveLiveActivitiesManager.shared.insertSync(.pomodoro)
        } else {
            ActiveLiveActivitiesManager.shared.removeSync(.pomodoro)
        }
    }

    // MARK: - Persistence

    /// Stored JSON (keys unchanged since the first version).
    private struct Snapshot: Codable {
        var phase: PomodoroPhase
        var status: Status
        var remainingSeconds: Int
        var phaseSeconds: Int
        var expiresAt: Date?
        var completedInCycle: Int
        var taskLabel: String
        var todayCount: Int
        var todayDay: String
    }

    private func save() {
        defer { if started { syncActivity() } }
        guard persistent else { return }
        let c = cycle
        let snapshot = Snapshot(phase: c.phase, status: c.status, remainingSeconds: c.remainingSeconds,
                                phaseSeconds: c.phaseSeconds, expiresAt: c.expiresAt,
                                completedInCycle: c.completedInCycle, taskLabel: taskLabel,
                                todayCount: c.todayCount, todayDay: c.todayDay)
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        var c = PomodoroCycle()
        c.phase = s.phase
        c.status = s.status
        c.phaseSeconds = s.phaseSeconds
        c.remainingSeconds = s.remainingSeconds
        c.expiresAt = s.expiresAt
        c.completedInCycle = s.completedInCycle
        c.todayCount = s.todayCount
        c.todayDay = s.todayDay
        let end = c.restore(now: Date(), config: config, calendar: .current)
        cycle = c
        taskLabel = s.taskLabel
        if let end { phaseEnded(end) }
    }

    #if DEBUG
    /// DEBUG gallery: an ephemeral store in a given state (nothing ticks, rings or is persisted).
    func debugSeed(phase: PomodoroPhase, status: Status, remaining: Int, total: Int,
                   completed: Int, today: Int, label: String, alert: PomodoroPhase? = nil) {
        var c = PomodoroCycle()
        c.phase = phase
        c.status = status
        c.phaseSeconds = total
        c.remainingSeconds = remaining
        c.expiresAt = nil
        c.completedInCycle = completed
        c.todayCount = today
        c.todayDay = PomodoroCycle.dayString(Date(), calendar: .current)
        cycle = c
        self.taskLabel = label
        self.alertPhase = alert
        stopTick()
    }
    #endif
}
