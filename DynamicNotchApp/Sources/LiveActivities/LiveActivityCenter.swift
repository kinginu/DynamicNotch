import SwiftUI

/// Starts the live-activity producers that run for the app's lifetime (called once from
/// AppDelegate after the notch windows exist).
enum LiveActivitiesStartup {
    @MainActor static func start() {
        LiveActivityCenter.shared.start()
        NextUpManager.shared.start()   // Next Up widget: "starts in N min" (only while the widget is in the Nook)
        KeepAwakeManager.shared.start() // Keep Awake widget: resumes a persisted session
        HUDMonitor.shared.start() // F5: volume / brightness HUD (`.hud`)
    }
}

/// The observable inputs of the closed-notch row: the settings snapshot that gates activities, the
/// activity currently holding the closed notch, and the monitors that request the battery,
/// calendar and timer activities.
///
/// Producers request activities through `ActiveLiveActivitiesManager` (media: MediaManager; tray:
/// the tray; fan alert: fan-control-integration.md (f); battery / calendar / timer: the monitors below;
/// Focus, Next Up, Keep Awake: their widgets' stores). The manager filters the requests with
/// `isAllowed(_:)`, and `currentActivity` picks the one that is drawn.
@MainActor @Observable
final class LiveActivityCenter {
    static let shared = LiveActivityCenter()

    // Settings snapshot, kept in sync with SettingsStore (written only on change).
    private(set) var liveSettings = SettingsStore[.liveActivitiesSettings]
    private(set) var batterySettings = SettingsStore[.batteryLiveActivitySettings]
    private(set) var calendarSettings = SettingsStore[.calendarLiveActivitySettings]

    let battery = BatteryActivityMonitor()
    let calendar = CalendarActivityMonitor()
    let timer = TimerActivityMonitor()

    /// Battery monitor (nil until `start()`).
    var power: PowerMonitor? { battery.power }
    /// Event shown by the `.calendar` activity.
    var upcomingEvent: CalendarActivityMonitor.UpcomingEvent? { calendar.upcomingEvent }
    /// Label of the timer that just ended.
    var expiredTimerLabel: String? { timer.expiredTimerLabel }

    @ObservationIgnored private var started = false
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    private var manager: ActiveLiveActivitiesManager { .shared }

    /// The activity drawn in the closed notch (nil: nothing, the notch stays notch-sized).
    var currentActivity: LiveActivity? {
        var candidates = manager.activeLiveActivities
        guard !candidates.isEmpty else { return nil }
        // As on the Dynamic Island, a counting timer yields the compact slot to any other activity
        // and shows as "minimal" beside it; a ringing alert keeps its priority.
        if candidates.count > 1, candidates.contains(.timerExpired), NookTimersStore.shared.alertingIDs.isEmpty {
            candidates.remove(.timerExpired)
        }
        return LiveActivitySelectionManager.shared.selectActivity(from: candidates, batteryStatus: power?.status)
    }

    /// The timer is requested but another activity holds the compact slot (Dynamic Island minimal).
    var timerIsMinimal: Bool {
        manager.activeLiveActivities.contains(.timerExpired) && currentActivity != .timerExpired
            && NookTimersStore.shared.islandEntry != nil
    }

    /// Whether the user's settings allow `activity` (`LiveActivityDescriptor.gate`).
    func isAllowed(_ activity: LiveActivity) -> Bool {
        let gate = activity.descriptor.gate
        if case .always = gate { return true }
        guard liveSettings.enabled, !liveSettings.disabledActivities.contains(activity.rawValue) else { return false }
        if case .liveActivitiesSettingsAnd(let isEnabled) = gate { return isEnabled(self) }
        return true
    }

    func start() {
        guard !started else { return }
        started = true

        manager.isAllowed = { [weak self] activity in
            MainActor.assumeIsolated { self?.isAllowed(activity) ?? true }
        }
        manager.recompute()

        // The media manager starts its MediaRemote listener on first access and then requests
        // `.media` itself.
        _ = MediaManager.shared

        battery.start(center: self)
        calendar.start(center: self)
        timer.start()
        PomodoroStore.shared.start() // Focus widget: restores a running session, requests `.pomodoro`

        observe(.liveActivitiesSettings) { $0.liveSettings = $1 }
        observe(.batteryLiveActivitySettings) { center, value in
            center.batterySettings = value
            center.battery.settingsChanged()
        }
        observe(.calendarLiveActivitySettings) { center, value in
            center.calendarSettings = value
            center.calendar.evaluate()
        }
        observe(.timerWidgetSettings) { center, _ in center.timer.sync() }
    }

    /// Request `.timerExpired` while a timer counts (if shown in the closed notch) or an alert rings.
    func syncTimerActivity() { timer.sync() }

    /// Re-evaluates the `.calendar` activity.
    func evaluateCalendar() { calendar.evaluate() }

    private func observe<Value: Equatable & StoredValue>(
        _ key: StoredKey<Value>,
        apply: @escaping (LiveActivityCenter, Value) -> Void
    ) {
        tasks.append(Task { @MainActor [weak self] in
            for await value in SettingsStore.updates(key, initial: false) {
                guard let self else { return }
                apply(self, value)
                self.manager.recompute()
            }
        })
    }

    // MARK: Debug

    /// DEBUG hooks (Support/DebugHooks-B.swift): force an activity on/off, bypassing the producers.
    func debugForce(_ activity: LiveActivity, on: Bool) {
        if on {
            if activity == .calendar { calendar.debugEnsureEvent() }
            manager.insertSync(activity)
        } else {
            manager.removeSync(activity)
        }
    }

    func debugClear() {
        for activity in manager.requestedActivities { manager.removeSync(activity) }
    }

    var debugDescription: String {
        "requested=\(manager.requestedActivities.map(\.rawValue).sorted()) visible=\(manager.activeLiveActivities.map(\.rawValue).sorted()) current=\(currentActivity?.rawValue ?? "nil") battery=\(power?.status.map { "\($0.pct)% charging=\($0.isCharging)" } ?? "nil") event=\(upcomingEvent?.title ?? "nil") media=\(MediaManager.shared.track.title)/\(MediaManager.shared.isPlaying) disabled=\(liveSettings.disabledActivities.sorted())/stored=\(SettingsStore[.liveActivitiesSettings].disabledActivities.sorted()) enabled=\(liveSettings.enabled)"
    }
}
