// Tests of the Focus (Pomodoro) state machine (Sources/PomodoroEngine.swift): start / pause /
// resume / tick / phase end / skip / reset / auto-start / settings changes / relaunch catch-up and
// the "today" count. The clock is a plain `Date` the tests advance; the calendar is UTC.
import Foundation
import Testing
@testable import DynamicNotchApp   // the CLT harness library and the Xcode test-support library

private let t0 = Date(timeIntervalSince1970: 1_792_400_000)   // 2026-10-19 08:53:20 UTC
private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

/// 25 / 5 / 15 min, long break every 4 (the defaults).
private let standard = PomodoroConfig()
/// Short phases for readable arithmetic: focus 100 s, short 20 s, long 60 s, long break every 2.
private let quick = PomodoroConfig(focusSeconds: 100, shortBreakSeconds: 20, longBreakSeconds: 60, longBreakEvery: 2)

/// Drives a cycle with a moving clock.
private struct Driver {
    var cycle: PomodoroCycle
    var now = t0
    var config: PomodoroConfig
    var ends: [PomodoroPhaseEnd] = []

    init(_ config: PomodoroConfig) {
        self.config = config
        cycle = PomodoroCycle(config: config)
    }

    mutating func advance(_ seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
        if let end = cycle.tick(now: now, config: config, calendar: utc) { ends.append(end) }
    }

    @discardableResult mutating func start() -> Bool { cycle.resume(now: now, config: config) }
    @discardableResult mutating func pause() -> Bool { cycle.pause(now: now) }

    /// Runs the current phase to its end.
    mutating func complete() {
        if !cycle.isRunning { start() }
        advance(TimeInterval(cycle.remainingSeconds))
    }

    var state: (PomodoroPhase, PomodoroStatus, Int) { (cycle.phase, cycle.status, cycle.completedInCycle) }
}

@Suite("Pomodoro state machine")
struct PomodoroEngineTests {

    // MARK: Basics

    @Test func initialState() {
        let c = PomodoroCycle(config: standard)
        #expect(c.phase == .focus)
        #expect(c.status == .idle)
        #expect(c.remainingSeconds == 25 * 60)
        #expect(c.phaseSeconds == 25 * 60)
        #expect(c.progress == 1)
        #expect(c.expiresAt == nil)
        #expect(c.nextPhase(standard) == .shortBreak)
    }

    @Test func configLengthsHaveAFloor() {
        let zero = PomodoroConfig(focusSeconds: 0, shortBreakSeconds: -5, longBreakSeconds: 0, longBreakEvery: 0)
        #expect(zero.seconds(of: .focus) == 1)
        #expect(zero.seconds(of: .shortBreak) == 1)
        #expect(zero.cycleLength == 1)
        #expect(PomodoroCycle(config: zero).nextPhase(zero) == .longBreak)   // every session completes a cycle
    }

    // MARK: Transitions (table)

    /// One step of a scripted session and the state expected after it.
    enum Step: Sendable {
        case start, pause, skip, reset, complete
        case advance(TimeInterval)
    }

    struct Script: CustomTestStringConvertible, Sendable {
        var name: String
        var steps: [Step]
        var phase: PomodoroPhase
        var status: PomodoroStatus
        var completed: Int
        var remaining: Int
        var testDescription: String { name }
    }

    static let scripts: [Script] = [
        .init(name: "idle → start → running", steps: [.start], phase: .focus, status: .running, completed: 0, remaining: 100),
        .init(name: "running ticks down", steps: [.start, .advance(30.2)], phase: .focus, status: .running, completed: 0, remaining: 70),
        .init(name: "pause keeps what is left", steps: [.start, .advance(40), .pause], phase: .focus, status: .paused, completed: 0, remaining: 60),
        .init(name: "a paused clock does not move", steps: [.start, .advance(40), .pause, .advance(500)], phase: .focus, status: .paused, completed: 0, remaining: 60),
        .init(name: "resume continues", steps: [.start, .advance(40), .pause, .advance(500), .start, .advance(10)], phase: .focus, status: .running, completed: 0, remaining: 50),
        .init(name: "pause rounds up, at least 1 s", steps: [.start, .advance(99.9), .pause], phase: .focus, status: .paused, completed: 0, remaining: 1),
        .init(name: "focus ends → short break waits", steps: [.complete], phase: .shortBreak, status: .idle, completed: 1, remaining: 20),
        .init(name: "short break ends → focus waits", steps: [.complete, .complete], phase: .focus, status: .idle, completed: 1, remaining: 100),
        .init(name: "2nd focus completes the cycle → long break", steps: [.complete, .complete, .complete], phase: .longBreak, status: .idle, completed: 2, remaining: 60),
        .init(name: "long break ends → new cycle", steps: [.complete, .complete, .complete, .complete], phase: .focus, status: .idle, completed: 0, remaining: 100),
        .init(name: "skip focus → short break, not counted", steps: [.start, .advance(10), .skip], phase: .shortBreak, status: .idle, completed: 0, remaining: 20),
        .init(name: "skip never earns the long break", steps: [.complete, .complete, .skip], phase: .shortBreak, status: .idle, completed: 1, remaining: 20),
        .init(name: "skip short break → focus", steps: [.complete, .skip], phase: .focus, status: .idle, completed: 1, remaining: 100),
        .init(name: "skip long break → focus, cycle reset", steps: [.complete, .complete, .complete, .skip], phase: .focus, status: .idle, completed: 0, remaining: 100),
        .init(name: "skip an idle phase", steps: [.skip], phase: .shortBreak, status: .idle, completed: 0, remaining: 20),
        .init(name: "skip while paused", steps: [.start, .advance(5), .pause, .skip], phase: .shortBreak, status: .idle, completed: 0, remaining: 20),
        .init(name: "reset mid-cycle", steps: [.complete, .complete, .start, .advance(5), .reset], phase: .focus, status: .idle, completed: 0, remaining: 100),
        .init(name: "reset from a break", steps: [.complete, .start, .reset], phase: .focus, status: .idle, completed: 0, remaining: 100),
        .init(name: "a late tick finishes once", steps: [.start, .advance(1000)], phase: .shortBreak, status: .idle, completed: 1, remaining: 20),
        .init(name: "start after a phase end", steps: [.complete, .start, .advance(5)], phase: .shortBreak, status: .running, completed: 1, remaining: 15),
    ]

    @Test(arguments: scripts)
    func transition(_ script: Script) {
        var d = Driver(quick)
        for step in script.steps {
            switch step {
            case .start: d.start()
            case .pause: d.pause()
            case .skip: d.cycle.skip(config: d.config)
            case .reset: d.cycle.reset(config: d.config)
            case .complete: d.complete()
            case .advance(let s): d.advance(s)
            }
        }
        #expect(d.cycle.phase == script.phase)
        #expect(d.cycle.status == script.status)
        #expect(d.cycle.completedInCycle == script.completed)
        #expect(d.cycle.remainingSeconds == script.remaining)
        #expect((d.cycle.expiresAt != nil) == (script.status == .running))
    }

    // MARK: Guards

    @Test func startWhileRunningIsANoOp() {
        var d = Driver(quick)
        let started = d.start()
        #expect(started)
        let expires = d.cycle.expiresAt
        d.advance(10)
        let restarted = d.start()
        #expect(!restarted)
        #expect(d.cycle.expiresAt == expires)
    }

    @Test func pauseWhenNotRunningIsANoOp() {
        var d = Driver(quick)
        let paused = d.pause()
        #expect(!paused)
        #expect(d.cycle.status == .idle)
    }

    @Test func tickWhenNotRunningDoesNothing() {
        var d = Driver(quick)
        let before = d.cycle
        d.advance(1000)
        #expect(d.cycle == before)
        #expect(d.ends.isEmpty)
    }

    // MARK: Phase ends

    @Test func phaseEndReport() {
        var d = Driver(quick)
        d.complete()
        #expect(d.ends == [PomodoroPhaseEnd(ended: .focus, next: .shortBreak, autoStarted: false, rings: true)])
        d.complete(); d.complete()
        #expect(d.ends.last == PomodoroPhaseEnd(ended: .focus, next: .longBreak, autoStarted: false, rings: true))
    }

    @Test func autoStartBreaks() {
        var config = quick
        config.autoStartBreaks = true
        var d = Driver(config)
        d.complete()
        #expect(d.state == (.shortBreak, .running, 1))
        #expect(d.ends.last?.autoStarted == true)
        #expect(d.cycle.expiresAt == d.now.addingTimeInterval(20))
        // the break ends: focus does not auto-start
        d.advance(20)
        #expect(d.state == (.focus, .idle, 1))
        #expect(d.ends.last?.autoStarted == false)
    }

    @Test func autoStartFocus() {
        var config = quick
        config.autoStartFocus = true
        var d = Driver(config)
        d.complete()
        #expect(d.state == (.shortBreak, .idle, 1))
        d.complete()
        #expect(d.state == (.focus, .running, 1))
        #expect(d.cycle.remainingSeconds == 100)
    }

    @Test func fullyAutomaticCycle() {
        var config = quick
        config.autoStartBreaks = true
        config.autoStartFocus = true
        var d = Driver(config)
        d.start()
        // focus 100 → short 20 → focus 100 → long 60 → focus …
        d.advance(100); #expect(d.state == (.shortBreak, .running, 1))
        d.advance(20); #expect(d.state == (.focus, .running, 1))
        d.advance(100); #expect(d.state == (.longBreak, .running, 2))
        d.advance(60); #expect(d.state == (.focus, .running, 0))
        #expect(d.ends.map(\.ended) == [.focus, .shortBreak, .focus, .longBreak])
        let allAuto = d.ends.allSatisfy { $0.autoStarted }
        #expect(allAuto)
    }

    // MARK: Settings changes

    @Test func configChangeAppliesToIdlePhase() {
        var c = PomodoroCycle(config: quick)
        var longer = quick
        longer.focusSeconds = 300
        c.configChanged(longer)
        #expect(c.remainingSeconds == 300)
        #expect(c.phaseSeconds == 300)
    }

    @Test func configChangeKeepsRunningPhase() {
        var d = Driver(quick)
        d.start()
        d.advance(10)
        var longer = quick
        longer.focusSeconds = 300
        d.cycle.configChanged(longer)
        d.config = longer
        #expect(d.cycle.phaseSeconds == 100)
        #expect(d.cycle.remainingSeconds == 90)
        // the next phase uses the new settings
        d.advance(90)
        d.complete()
        #expect(d.cycle.phase == .focus)
        #expect(d.cycle.remainingSeconds == 300)
    }

    @Test func loweredCycleLengthTakesEffect() {
        var d = Driver(standard)
        d.complete(); d.complete(); d.complete(); d.complete()   // two focus sessions done
        #expect(d.cycle.completedInCycle == 2)
        d.config.longBreakEvery = 2                                // already past the new length
        #expect(d.cycle.nextPhase(d.config) == .longBreak)
        d.complete()
        #expect(d.cycle.phase == .longBreak)
    }

    // MARK: Progress

    @Test func progress() {
        var d = Driver(quick)
        d.start()
        d.advance(25)
        #expect(d.cycle.progress == 0.75)
        d.advance(75)
        #expect(d.cycle.progress == 1)    // next phase, full
    }

    // MARK: Today's count

    @Test func todayCount() {
        var d = Driver(quick)
        d.complete(); d.complete(); d.complete()
        #expect(d.cycle.completedToday(now: d.now, calendar: utc) == 2)
        #expect(d.cycle.todayDay == "2026-10-19")
        // next day: shows 0 until a session completes, then restarts at 1
        let tomorrow = d.now.addingTimeInterval(86_400)
        #expect(d.cycle.completedToday(now: tomorrow, calendar: utc) == 0)
        d.now = tomorrow
        d.cycle.reset(config: d.config)
        d.complete()
        #expect(d.cycle.completedToday(now: d.now, calendar: utc) == 1)
        #expect(d.cycle.todayDay == "2026-10-20")
    }

    @Test func resetKeepsTodayCount() {
        var d = Driver(quick)
        d.complete()
        d.cycle.reset(config: d.config)
        #expect(d.cycle.completedToday(now: d.now, calendar: utc) == 1)
    }

    @Test func skippedFocusIsNotCounted() {
        var d = Driver(quick)
        d.start()
        d.cycle.skip(config: d.config)
        #expect(d.cycle.completedToday(now: d.now, calendar: utc) == 0)
    }

    @Test func dayString() {
        #expect(PomodoroCycle.dayString(t0, calendar: utc) == "2026-10-19")
        var tokyo = utc
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        #expect(PomodoroCycle.dayString(Date(timeIntervalSince1970: 1_792_450_000), calendar: tokyo) == "2026-10-20")
    }

    // MARK: Relaunch (restore)

    @Test func restoreContinuesARunningPhase() {
        var d = Driver(quick)
        d.start()
        var saved = d.cycle
        let end = saved.restore(now: t0.addingTimeInterval(30.5), config: quick, calendar: utc)
        #expect(end == nil)
        #expect(saved.status == .running)
        #expect(saved.remainingSeconds == 70)
    }

    @Test func restoreRingsForAJustEndedPhase() {
        var d = Driver(quick)
        d.start()
        var saved = d.cycle
        let end = saved.restore(now: t0.addingTimeInterval(130), config: quick, calendar: utc)   // 30 s late
        #expect(end == PomodoroPhaseEnd(ended: .focus, next: .shortBreak, autoStarted: false, rings: true))
        #expect(saved.phase == .shortBreak)
        #expect(saved.completedInCycle == 1)
    }

    @Test func restoreCountsAnOldPhaseSilently() {
        var config = quick
        config.autoStartBreaks = true
        var d = Driver(config)
        d.start()
        var saved = d.cycle
        let end = saved.restore(now: t0.addingTimeInterval(100 + 3600), config: config, calendar: utc)
        // counted, but no alert and no auto-start an hour later
        #expect(end == PomodoroPhaseEnd(ended: .focus, next: .shortBreak, autoStarted: false, rings: false))
        #expect(saved.status == .idle)
        #expect(saved.completedInCycle == 1)
    }

    @Test func restoreAutoStartsWhenJustEnded() {
        var config = quick
        config.autoStartBreaks = true
        var d = Driver(config)
        d.start()
        var saved = d.cycle
        let now = t0.addingTimeInterval(110)
        let end = saved.restore(now: now, config: config, calendar: utc)
        #expect(end?.autoStarted == true)
        #expect(saved.status == .running)
        #expect(saved.expiresAt == now.addingTimeInterval(20))
    }

    /// A focus session that expired before midnight counts for that day, not for the relaunch day.
    @Test func restoreCountsOnTheDayThePhaseEnded() {
        let lateEvening = Date(timeIntervalSince1970: 1_792_454_000)       // 2026-10-19 23:53:20 UTC
        var c = PomodoroCycle(config: quick)
        c.resume(now: lateEvening, config: quick)                          // ends 23:55:00
        let nextMorning = lateEvening.addingTimeInterval(8 * 3600)
        _ = c.restore(now: nextMorning, config: quick, calendar: utc)
        #expect(c.todayDay == "2026-10-19")
        #expect(c.completedToday(now: nextMorning, calendar: utc) == 0)
        #expect(c.completedToday(now: lateEvening, calendar: utc) == 1)
    }

    @Test func restoreSanitisesStoredValues() {
        var c = PomodoroCycle(config: quick)
        c.status = .paused
        c.phaseSeconds = 0
        c.remainingSeconds = -4
        c.completedInCycle = -1
        let end = c.restore(now: t0, config: quick, calendar: utc)
        #expect(end == nil)
        #expect(c.phaseSeconds == 1)
        #expect(c.remainingSeconds == 0)
        #expect(c.completedInCycle == 0)
    }

    @Test func restoreRunningWithoutExpiryFinishesSilently() {
        var c = PomodoroCycle(config: quick)
        c.status = .running
        c.expiresAt = nil
        let end = c.restore(now: t0, config: quick, calendar: utc)
        #expect(end?.rings == false)
        #expect(c.phase == .shortBreak)
    }
}
