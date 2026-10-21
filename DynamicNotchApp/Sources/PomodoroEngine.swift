// Focus (Pomodoro) session state machine (2026-10-20). Pure Foundation: no timers, sounds,
// UserDefaults or settings access — the clock (`now`), the calendar (today's count) and the cycle
// configuration are passed in. PomodoroStore owns one `PomodoroCycle` and adds the side effects
// (0.5 s tick, end alert, persistence, the closed-notch activity).
// Tests: Tests/EngineTests/PomodoroEngineTests.swift.
//
// States: status ∈ {idle, running, paused} × phase ∈ {focus, shortBreak, longBreak}.
//
//   start / resume   idle → running: the phase gets its length from the config (fixed until the
//                    phase ends); paused → running: continues with what was left.
//                    `expiresAt` = now + remaining.
//   pause            running → paused: remaining = ⌈expiresAt − now⌉ (at least 1 s).
//   tick(now)        running: remaining = ⌈expiresAt − now⌉; at 0 the phase FINISHES (below).
//   finish           focus → completedInCycle += 1, today's count += 1 (on the day the phase
//                    expired), next = longBreak when completedInCycle reaches `longBreakEvery`,
//                    else shortBreak. shortBreak → focus. longBreak → focus, completedInCycle = 0.
//                    The next phase starts at once when the matching auto-start option is on
//                    (breaks after focus, focus after breaks) and the end is "live" (it rings);
//                    otherwise it waits idle.
//   skip             ends the phase WITHOUT counting it: focus → shortBreak (never the long break:
//                    the skipped session did not complete the cycle), breaks → focus (a skipped
//                    long break still resets the cycle). The next phase waits idle.
//   reset            idle focus at the start of a new cycle (completedInCycle = 0; today's count kept).
//   configChanged    an idle phase takes the new length at once; a running / paused one keeps its own.
//   restore(now)     after a relaunch: a running phase that is still in the future continues; one
//                    that expired meanwhile finishes, and it rings (and may auto-start the next
//                    phase) only if it expired less than `lateRingLimit` ago.
import Foundation

enum PomodoroPhase: String, Codable, Equatable, Hashable, CaseIterable {
    case focus, shortBreak, longBreak

    var isBreak: Bool { self != .focus }

    var title: String {
        switch self {
        case .focus: return String(localized: "Focus")
        case .shortBreak: return String(localized: "Short Break")
        case .longBreak: return String(localized: "Long Break")
        }
    }
}

enum PomodoroStatus: String, Codable, Equatable {
    case idle, running, paused
}

/// Lengths and options of a cycle (PomodoroWidgetSettings, in seconds).
struct PomodoroConfig: Equatable {
    var focusSeconds: Int = 25 * 60
    var shortBreakSeconds: Int = 5 * 60
    var longBreakSeconds: Int = 15 * 60
    /// A long break follows every `longBreakEvery` completed focus sessions (at least 1).
    var longBreakEvery: Int = 4
    var autoStartBreaks: Bool = false
    var autoStartFocus: Bool = false

    /// Length of `phase` (at least one second).
    func seconds(of phase: PomodoroPhase) -> Int {
        switch phase {
        case .focus: return max(1, focusSeconds)
        case .shortBreak: return max(1, shortBreakSeconds)
        case .longBreak: return max(1, longBreakSeconds)
        }
    }

    var cycleLength: Int { max(1, longBreakEvery) }

    /// Whether the phase after `ended` starts by itself.
    func autoStarts(after ended: PomodoroPhase) -> Bool {
        ended == .focus ? autoStartBreaks : autoStartFocus
    }
}

/// What happened when a phase reached its end.
struct PomodoroPhaseEnd: Equatable {
    var ended: PomodoroPhase
    var next: PomodoroPhase
    /// The next phase is already running (auto-start).
    var autoStarted: Bool
    /// The end should be signalled (sound / alert): false for a phase that ended long ago.
    var rings: Bool
}

/// The session cycle (value type; every transition takes the clock and the config).
struct PomodoroCycle: Equatable {
    /// A phase that ended at most this long before `restore` still rings.
    static let lateRingLimit: TimeInterval = 60

    var phase: PomodoroPhase = .focus
    var status: PomodoroStatus = .idle
    /// Seconds left in the current phase.
    var remainingSeconds: Int
    /// Length of the current phase, fixed when the phase starts.
    var phaseSeconds: Int
    /// When the running phase ends (nil unless running).
    var expiresAt: Date?
    /// Focus sessions completed in the current cycle.
    var completedInCycle: Int = 0
    /// Focus sessions completed on `todayDay` ("yyyy-MM-dd").
    var todayCount: Int = 0
    var todayDay: String = ""

    /// An idle focus session of `config`'s length.
    init(config: PomodoroConfig = PomodoroConfig()) {
        phaseSeconds = config.seconds(of: .focus)
        remainingSeconds = phaseSeconds
    }

    // MARK: Derived

    var isRunning: Bool { status == .running }
    var isPaused: Bool { status == .paused }

    /// Fraction of the current phase left (1 = full).
    var progress: Double {
        guard phaseSeconds > 0 else { return 0 }
        return Double(max(0, remainingSeconds)) / Double(phaseSeconds)
    }

    /// The phase after the current one ends (a focus session ends in a long break when it completes
    /// the cycle).
    func nextPhase(_ config: PomodoroConfig) -> PomodoroPhase {
        switch phase {
        case .focus: return completedInCycle + 1 >= config.cycleLength ? .longBreak : .shortBreak
        case .shortBreak, .longBreak: return .focus
        }
    }

    /// Focus sessions completed on the day of `now`.
    func completedToday(now: Date, calendar: Calendar) -> Int {
        todayDay == Self.dayString(now, calendar: calendar) ? todayCount : 0
    }

    static func dayString(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    // MARK: Transitions

    /// Start (idle) or resume (paused). Returns false when nothing changed (already running).
    @discardableResult
    mutating func resume(now: Date, config: PomodoroConfig) -> Bool {
        guard status != .running else { return false }
        if status == .idle {
            phaseSeconds = config.seconds(of: phase)
            remainingSeconds = phaseSeconds
        }
        guard remainingSeconds > 0 else { return false }
        expiresAt = now.addingTimeInterval(TimeInterval(remainingSeconds))
        status = .running
        return true
    }

    /// Returns false when not running.
    @discardableResult
    mutating func pause(now: Date) -> Bool {
        guard status == .running else { return false }
        if let expiresAt { remainingSeconds = max(1, Int(ceil(expiresAt.timeIntervalSince(now)))) }
        expiresAt = nil
        status = .paused
        return true
    }

    /// Ends the current phase without counting it; the next one waits idle.
    mutating func skip(config: PomodoroConfig) {
        let next: PomodoroPhase = phase == .focus ? .shortBreak : .focus
        if phase == .longBreak { completedInCycle = 0 }
        enter(next, config: config)
    }

    /// Back to an idle focus session at the start of a new cycle (today's count is kept).
    mutating func reset(config: PomodoroConfig) {
        completedInCycle = 0
        enter(.focus, config: config)
    }

    /// The settings changed: an idle phase takes its new length.
    mutating func configChanged(_ config: PomodoroConfig) {
        guard status == .idle else { return }
        phaseSeconds = config.seconds(of: phase)
        remainingSeconds = phaseSeconds
    }

    /// Advances the running clock; returns the phase end when it reached zero.
    mutating func tick(now: Date, config: PomodoroConfig, calendar: Calendar) -> PomodoroPhaseEnd? {
        guard status == .running, let expiresAt else { return nil }
        let left = expiresAt.timeIntervalSince(now)
        if left <= 0 {
            remainingSeconds = 0
            return finish(now: now, config: config, calendar: calendar, rings: true)
        }
        remainingSeconds = Int(ceil(left))
        return nil
    }

    /// After loading a saved state: catches up with a phase that ran while the app was not running.
    mutating func restore(now: Date, config: PomodoroConfig, calendar: Calendar) -> PomodoroPhaseEnd? {
        phaseSeconds = max(1, phaseSeconds)
        remainingSeconds = max(0, remainingSeconds)
        completedInCycle = max(0, completedInCycle)
        guard status == .running else { return nil }
        if let expiresAt, expiresAt > now {
            remainingSeconds = Int(ceil(expiresAt.timeIntervalSince(now)))
            return nil
        }
        // ended while the app was not running: count it, but ring only if it just ended
        let late = expiresAt.map { now.timeIntervalSince($0) } ?? .infinity
        remainingSeconds = 0
        return finish(now: now, config: config, calendar: calendar, rings: late < Self.lateRingLimit)
    }

    /// The running phase reached zero.
    private mutating func finish(now: Date, config: PomodoroConfig, calendar: Calendar, rings: Bool) -> PomodoroPhaseEnd {
        let ended = phase
        let next = nextPhase(config)
        // the session completed when it expired, not when the tick or the relaunch noticed it
        let completedAt = min(expiresAt ?? now, now)
        if ended == .focus {
            completedInCycle += 1
            recordCompleted(on: completedAt, calendar: calendar)
        } else if ended == .longBreak {
            completedInCycle = 0
        }
        let auto = config.autoStarts(after: ended) && rings
        enter(next, config: config)
        if auto { resume(now: now, config: config) }
        return PomodoroPhaseEnd(ended: ended, next: next, autoStarted: auto, rings: rings)
    }

    private mutating func enter(_ next: PomodoroPhase, config: PomodoroConfig) {
        phase = next
        phaseSeconds = config.seconds(of: next)
        remainingSeconds = phaseSeconds
        expiresAt = nil
        status = .idle
    }

    private mutating func recordCompleted(on date: Date, calendar: Calendar) {
        let day = Self.dayString(date, calendar: calendar)
        if todayDay != day {
            // a newer day starts a new count; a session that ended on an older day than the one
            // already counted (relaunch after midnight) is not today's
            guard day > todayDay else { return }
            todayDay = day
            todayCount = 0
        }
        todayCount += 1
    }
}
