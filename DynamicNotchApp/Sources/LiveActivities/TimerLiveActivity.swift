import Foundation
import Observation

/// Requests `.timerExpired`, modelled on the iOS Dynamic Island timer (docs/ios-timer-reference.md):
/// while a timer counts or is paused (if "Show in closed notch" is on: compact ring | remaining
/// time, or a minimal ring beside another activity) and while an ended timer's alert rings
/// (bell + label | Stop). `NookTimersStore.shared` owns the timers and the alert;
/// `NookTimerExpiryMonitor` makes the end exact, also while the notch is closed.
@MainActor @Observable
final class TimerActivityMonitor {
    /// Label of the timer that just ended.
    private(set) var expiredTimerLabel: String? = nil

    @ObservationIgnored private let expiryMonitor = NookTimerExpiryMonitor()

    private var manager: ActiveLiveActivitiesManager { .shared }

    func start() {
        expiryMonitor.onExpired = { [weak self] label in
            MainActor.assumeIsolated { self?.timerExpired(label: label) }
        }
        expiryMonitor.start()
        NookTimersStore.shared.onActivityChange = {
            DispatchQueue.main.async { LiveActivityCenter.shared.timer.sync() }
        }
        sync()
    }

    /// Request `.timerExpired` while a timer counts (if shown in the closed notch) or an alert rings.
    func sync() {
        let store = NookTimersStore.shared
        let show = !store.alertingIDs.isEmpty
            || (store.islandEntry != nil && SettingsStore[.timerWidgetSettings].showInClosedNotch)
        if show { manager.insertSync(.timerExpired) } else { manager.removeSync(.timerExpired) }
    }

    private func timerExpired(label: String) {
        let text = label.isEmpty ? nil : label
        if expiredTimerLabel != text { expiredTimerLabel = text }
        // The store owns the alert (it rings until Stop or the alert duration); let it notice the
        // end now instead of on its next 0.5 s tick, then mirror its state.
        NookTimersStore.shared.checkNow()
        sync()
    }
}

/// Announces the end of a running Nook timer exactly, whether or not the notch is open.
///
/// Reads the persisted snapshot of `NookTimersStore` (`nook_timers_snap`) and arms one one-shot
/// Timer for the earliest running timer; re-reads the snapshot when UserDefaults changes (only
/// when the bytes changed). The store is app-lifetime (AppDelegate creates `.shared` at launch),
/// so its own tick may mark a timer ended before this monitor fires — see `rearm()`.
final class NookTimerExpiryMonitor {
    var onExpired: ((String) -> Void)?

    private struct Snapshot: Decodable {
        let id: UUID
        let label: String
        let state: String
        let expiresAt: Date?
    }

    private let key = "nook_timers_snap"
    private var lastData: Data?
    private var armed: Timer?
    private var announced: Set<String> = []
    private var lastRunning: [Snapshot] = []
    private var observer: NSObjectProtocol?

    func start() {
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.reload() }
        reload()
    }

    private func reload() {
        let data = UserDefaults.standard.data(forKey: key)
        guard data != lastData else { return }
        lastData = data
        rearm()
    }

    private func pending() -> [Snapshot] {
        guard let data = lastData, let list = try? JSONDecoder().decode([Snapshot].self, from: data) else { return [] }
        return list.filter { $0.state == "running" && $0.expiresAt != nil }
    }

    private func rearm() {
        armed?.invalidate()
        armed = nil
        let now = Date()
        let running = pending()
        // The store's 0.5 s tick marks an ended timer as no longer running (and saves) — often
        // before the armed Timer below fires (tolerance 0.2 s). That save lands here and would
        // silently drop the entry, so announce any timer that left the running set right around
        // its expiry instead (a timer cancelled early has its expiry in the future and is not
        // announced).
        for gone in lastRunning where !announced.contains(tag(gone)) && !running.contains(where: { $0.id == gone.id }) {
            guard let expiresAt = gone.expiresAt else { continue }
            let late = now.timeIntervalSince(expiresAt)
            if late >= -0.5 && late < 5 {
                onExpired?(gone.label)
            }
        }
        lastRunning = running
        // forget timers that are no longer running
        announced = announced.filter { key in running.contains { tag($0) == key } }
        guard let next = running.filter({ !announced.contains(tag($0)) }).min(by: { $0.expiresAt! < $1.expiresAt! }) else { return }
        let fire = max(next.expiresAt!, now.addingTimeInterval(0.05))
        let timer = Timer(fire: fire, interval: 0, repeats: false) { [weak self] _ in
            guard let self else { return }
            // only announce timers that actually ended (not ones that were long overdue at launch)
            if now.timeIntervalSince(next.expiresAt!) < 60 {
                self.onExpired?(next.label)
            }
            self.announced.insert(self.tag(next))
            self.rearm()
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        armed = timer
    }

    private func tag(_ s: Snapshot) -> String { "\(s.id.uuidString)@\(s.expiresAt?.timeIntervalSinceReferenceDate ?? 0)" }
}
