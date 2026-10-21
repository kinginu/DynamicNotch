// NookTimersStore — the Timer widget's timers, modelled on the iOS Clock / Dynamic Island timer.
//
// App-lifetime store (`.shared`, created at launch) so timers keep running and ring while the notch
// is closed. Running timers count down on a 0.5 s tick that only runs while a timer runs; a timer
// that reaches 0 becomes ended (`.cancelled`) and rings — the "When Timer Ends" sound repeats every
// `ringInterval` until Stop or the alert duration passes. Started durations are kept in Recents.
//
// Persistence (UserDefaults): the timers as a JSON snapshot under "nook_timers_snap" (also read by
// NookTimerExpiryMonitor to fire exactly at the end) and the Recents under "nook_timers_recents".
//
// State meanings: `.running` counting down (`expiresAt` set); `.idle` paused (`expiresAt` nil,
// `remainingSeconds` kept); `.cancelled` / `.expired` ended.
import AppKit
import Foundation
import Observation
import os

private let logger = Logger(subsystem: "com.example.dynamicnotch.DynamicNotch", category: "timer")

@MainActor
@Observable
final class NookTimersStore {
    static let shared = NookTimersStore()

    /// All timers, in creation order.
    private(set) var timers: [TimerEntry] = []

    /// Recently started durations (iOS "Recents"): newest first, at most `maxRecents`, persisted.
    private(set) var recents: [Recent] = []

    /// Ended timers whose alert is showing (ringing) — newest last. Not persisted.
    private(set) var alertingIDs: [UUID] = []

    /// Called after any change that affects the closed-notch presentation (start / pause / cancel /
    /// end / stop). The timer live activity uses it to request or remove itself.
    @ObservationIgnored var onActivityChange: (() -> Void)? = nil

    struct Recent: Codable, Hashable, Identifiable {
        var seconds: Int
        var label: String
        var id: String { "\(seconds)|\(label)" }
    }

    static let maxRecents = 6
    static let ringInterval: TimeInterval = 2.5

    private static let snapshotKey = "nook_timers_snap"
    private static let recentsKey = "nook_timers_recents"

    /// false: neither loads nor saves (DEBUG gallery / settings preview stores).
    @ObservationIgnored private let persistent: Bool
    @ObservationIgnored private var tickTimer: Timer? = nil
    @ObservationIgnored private var ringTimer: Timer? = nil
    @ObservationIgnored private var alertDeadline: Date? = nil

    // MARK: - Init

    init(persistent: Bool = true) {
        self.persistent = persistent
        if persistent {
            load()
            loadRecents()
        }
        if timers.contains(where: { $0.state == .running }) {
            startTick()
        }
    }

    // MARK: - Timers

    /// Creates a timer and starts it right away (and remembers the duration in Recents).
    func add(label: String, totalSeconds: Int) {
        let entry = TimerEntry(label: label, totalSeconds: totalSeconds)
        timers.append(entry)
        start(entry)
        rememberRecent(seconds: totalSeconds, label: label)
    }

    /// Removes an ended timer (and silences its alert).
    func dismissExpired(_ entry: TimerEntry) {
        remove(entry)
    }

    /// Removes a timer, whatever its state.
    func cancel(_ entry: TimerEntry) {
        remove(entry)
    }

    /// Pauses a running timer, freezing the precise remaining time.
    func pause(_ entry: TimerEntry) {
        guard entry.state == .running else { return }
        if let expiresAt = entry.expiresAt {
            entry.remainingSeconds = max(1, Int(ceil(expiresAt.timeIntervalSinceNow)))
        }
        entry.state = .idle
        entry.expiresAt = nil
        save()
    }

    /// Starts (or resumes) a timer that has time left.
    func start(_ entry: TimerEntry) {
        guard !entry.hasEnded, entry.remainingSeconds > 0 else { return }
        let now = Date()
        entry.expiresAt = now.addingTimeInterval(TimeInterval(entry.remainingSeconds))
        entry.startedAt = now
        if entry.state != .running {
            entry.state = .running
        }
        save()
        if tickTimer == nil {
            startTick()
        }
    }

    private func remove(_ entry: TimerEntry) {
        removeAlert(entry.id)
        timers.removeAll { $0.id == entry.id }
        save()
    }

    // MARK: - Dynamic Island helpers

    /// Ended timers whose alert is showing, oldest first.
    var alertingEntries: [TimerEntry] {
        alertingIDs.compactMap { id in timers.first { $0.id == id } }
    }

    /// The timer the closed notch shows while counting (iOS shows one timer in the Dynamic Island):
    /// the running timer that ends soonest, else the most recently paused one.
    var islandEntry: TimerEntry? {
        let running = timers.filter(\.isRunning)
        if let soonest = running.min(by: { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }) {
            return soonest
        }
        return timers.last(where: \.isPaused)
    }

    /// Whether the timer live activity should be shown in the closed notch at all.
    var hasIslandContent: Bool { !alertingIDs.isEmpty || islandEntry != nil }

    /// Re-evaluates the running timers now (e.g. when an exact one-shot timer fired).
    func checkNow() { tick() }

    /// Stops an ended timer's alert and removes it (iOS "Stop").
    func stop(_ entry: TimerEntry) { dismissExpired(entry) }

    /// Stops every ringing timer.
    func stopAllAlerts() {
        for entry in alertingEntries { dismissExpired(entry) }
    }

    /// Starts the same duration and label again (iOS "Repeat" on the timer alert).
    func repeatTimer(_ entry: TimerEntry) {
        let label = entry.label, seconds = entry.totalSeconds
        dismissExpired(entry)
        guard seconds > 0 else { return }
        add(label: label, totalSeconds: seconds)
    }

    // MARK: - Recents

    /// Starts a timer from a Recents entry.
    func start(_ recent: Recent) { add(label: recent.label, totalSeconds: recent.seconds) }

    func removeRecent(_ recent: Recent) {
        recents.removeAll { $0 == recent }
        saveRecents()
    }

    private func rememberRecent(seconds: Int, label: String) {
        guard seconds > 0 else { return }
        let item = Recent(seconds: seconds, label: label.trimmingCharacters(in: .whitespacesAndNewlines))
        var list = recents.filter { $0 != item }
        list.insert(item, at: 0)
        recents = Array(list.prefix(Self.maxRecents))
        saveRecents()
    }

    private func loadRecents() {
        guard let data = UserDefaults.standard.data(forKey: Self.recentsKey) else { return }
        do {
            recents = Array(try JSONDecoder().decode([Recent].self, from: data).prefix(Self.maxRecents))
        } catch {
            logger.error("timer recents unreadable, starting empty: \(String(describing: error), privacy: .public)")
        }
    }

    private func saveRecents() {
        guard persistent else { return }
        do {
            UserDefaults.standard.set(try JSONEncoder().encode(recents), forKey: Self.recentsKey)
        } catch {
            logger.error("timer recents not saved: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Ticking

    private func startTick() {
        tickTimer = Self.mainRunLoopTimer(interval: 0.5, repeats: true) { [weak self] in
            guard let self else { return false }
            self.tick()
            return true
        }
    }

    private func tick() {
        var changed = false
        for entry in timers {
            guard entry.state == .running, let expiresAt = entry.expiresAt else { continue }
            let timeRemaining = expiresAt.timeIntervalSinceNow
            if timeRemaining <= 0 {
                entry.remainingSeconds = 0
                entry.state = .cancelled
                entry.expiresAt = Date()
                // alert like iOS: the closed notch shows the ended timer with Stop, and the "When
                // Timer Ends" sound repeats until stopped or `alertSeconds` passes
                beginAlert(entry.id)
                changed = true
            } else {
                // ceil: rounding would show 0:00 for the last half second. A countdown change alone
                // is not persisted (`expiresAt` is).
                let newRemaining = Int(ceil(timeRemaining))
                if entry.remainingSeconds != newRemaining {
                    entry.remainingSeconds = newRemaining
                }
            }
        }
        if changed {
            save()
        }
        // stop ticking when nothing runs (restarted by start(_:))
        if !timers.contains(where: { $0.state == .running }) {
            tickTimer?.invalidate()
            tickTimer = nil
        }
    }

    // MARK: - Alerts

    private func beginAlert(_ id: UUID) {
        if !alertingIDs.contains(id) { alertingIDs.append(id) }
        let settings = SettingsStore[.timerWidgetSettings]
        if settings.soundName == TimerWidgetSettings.stopPlayingSound {
            // iOS "Stop Playing": pause the playing media instead of a sound
            if MediaManager.shared.isPlaying { MediaManager.shared.togglePlayPause() }
        }
        alertDeadline = settings.alertSeconds > 0 ? Date().addingTimeInterval(TimeInterval(settings.alertSeconds)) : nil
        playSound()
        guard ringTimer == nil else { return }
        // repeat the sound like an alarm until stopped or the alert times out
        ringTimer = Self.mainRunLoopTimer(interval: Self.ringInterval, repeats: true) { [weak self] in
            guard let self else { return false }
            self.ring()
            return true
        }
    }

    private func ring() {
        guard !alertingIDs.isEmpty else { stopRinging(); return }
        if let alertDeadline, Date() >= alertDeadline {
            // time out: dismiss the alerts (the durations stay in Recents)
            stopRinging()
            for entry in alertingEntries { dismissExpired(entry) }
            return
        }
        playSound()
    }

    private func removeAlert(_ id: UUID) {
        guard alertingIDs.contains(id) else { return }
        alertingIDs.removeAll { $0 == id }
        if alertingIDs.isEmpty { stopRinging() }
    }

    private func stopRinging() {
        ringTimer?.invalidate()
        ringTimer = nil
        alertDeadline = nil
    }

    /// Plays the "When Timer Ends" sound ("Glass" by default; nothing for "Stop Playing").
    private func playSound() {
        let name = SettingsStore[.timerWidgetSettings].soundName
        guard !name.isEmpty, name != TimerWidgetSettings.stopPlayingSound else { return }
        guard let sound = NSSound(named: name) ?? NSSound(named: "Glass") else {
            logger.error("timer sound \(name, privacy: .public) not found")
            return
        }
        sound.play()
    }

    /// A Timer on the main run loop (common modes, so it also fires during tracking). `action`
    /// returns false when its owner is gone; the timer then invalidates itself.
    private static func mainRunLoopTimer(interval: TimeInterval, repeats: Bool,
                                         _ action: @escaping @MainActor @Sendable () -> Bool) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats) { timer in
            let ownerAlive = MainActor.assumeIsolated { action() }
            if !ownerAlive { timer.invalidate() }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    // MARK: - Persistence

    /// Persisted form of a timer (key "nook_timers_snap"; NookTimerExpiryMonitor decodes it too).
    private struct SnapshotEntry: Codable {
        let id: UUID
        let label: String
        let totalSeconds: Int
        let remainingSeconds: Int
        let state: TimerEntry.State
        let startedAt: Date?
        let expiresAt: Date?
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.snapshotKey) else { return }
        let snapshots: [SnapshotEntry]
        do {
            snapshots = try JSONDecoder().decode([SnapshotEntry].self, from: data)
        } catch {
            logger.error("saved timers unreadable, starting empty: \(String(describing: error), privacy: .public)")
            return
        }
        let now = Date()
        timers = snapshots.map { snapshot in
            let entry = TimerEntry(id: snapshot.id, label: snapshot.label, totalSeconds: snapshot.totalSeconds)
            entry.remainingSeconds = snapshot.remainingSeconds
            entry.state = snapshot.state
            entry.startedAt = snapshot.startedAt
            entry.expiresAt = snapshot.expiresAt
            // a timer that ended more than a minute before launch is shown as ended without
            // ringing (one that ends around launch still rings on the first tick)
            if entry.state == .running, let expiresAt = entry.expiresAt, now.timeIntervalSince(expiresAt) > 60 {
                entry.state = .cancelled
                entry.remainingSeconds = 0
            }
            return entry
        }
    }

    /// Saves the timers and reports the change to `onActivityChange`.
    private func save() {
        defer { onActivityChange?() }
        guard persistent else { return }
        let snapshots = timers.map { entry in
            SnapshotEntry(id: entry.id, label: entry.label, totalSeconds: entry.totalSeconds,
                          remainingSeconds: entry.remainingSeconds, state: entry.state,
                          startedAt: entry.startedAt, expiresAt: entry.expiresAt)
        }
        do {
            UserDefaults.standard.set(try JSONEncoder().encode(snapshots), forKey: Self.snapshotKey)
        } catch {
            logger.error("timers not saved: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - DEBUG

    #if DEBUG
    /// DEBUG gallery: put an ephemeral store into a given state without timers running.
    func debugSeed(_ entries: [(label: String, total: Int, remaining: Int, state: TimerEntry.State)], alerting: Bool = false) {
        timers = entries.map { item in
            let entry = TimerEntry(label: item.label, totalSeconds: item.total)
            entry.remainingSeconds = item.remaining
            entry.state = item.state
            if item.state == .running { entry.expiresAt = Date().addingTimeInterval(TimeInterval(item.remaining)) }
            return entry
        }
        alertingIDs = alerting ? timers.filter(\.hasEnded).map(\.id) : []
        recents = [Recent(seconds: 300, label: ""), Recent(seconds: 900, label: "Tea"), Recent(seconds: 1500, label: "Focus")]
    }
    #endif
}
