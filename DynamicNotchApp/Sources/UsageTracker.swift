// Usage widget (2026-10-20): records how long each app is frontmost while the user is
// present, like Screen Time, from public APIs only and with no permission prompt:
//   - frontmost app: NSWorkspace.didActivateApplicationNotification (+ frontmostApplication at
//     start, after wake and after unlock);
//   - idle: CGEventSource.secondsSinceLastEventType(.combinedSessionState, any input) polled every
//     5 s; past the threshold (Settings, default 5 min) the time since the last input is not
//     counted, and counting resumes at the next input;
//   - sleep / wake: NSWorkspace.willSleep / didWake; lock / unlock: the distributed notifications
//     com.apple.screenIsLocked / com.apple.screenIsUnlocked (and fast user switching:
//     sessionDidResignActive / sessionDidBecomeActive). Each unlock is a pickup.
// The accounting itself is UsageAccountant (pure, unit-tested); totals go to UsageStore (SwiftData),
// saved every 30 s, on stop and at quit.
//
// Lifecycle: runs from launch while Settings ▸ Widgets ▸ Usage ▸ "Record app usage" is on, whether
// or not the widget is in the Nook; turning it off stops everything (the recorded data stays until
// "Clear Usage Data").
import AppKit
import CoreGraphics
import Observation

@MainActor
@Observable
final class UsageTracker {
    static let shared = UsageTracker()

    static let pollInterval: TimeInterval = 5
    static let flushInterval: TimeInterval = 30
    /// A gap this long between two ticks is not counted (the process was suspended or a sleep
    /// notification was missed).
    static let maximumGap: TimeInterval = 600
    /// Frontmost "apps" that mean nobody is using the Mac.
    static let ignoredAppIDs: Set<String> = ["com.apple.loginwindow", "com.apple.ScreenSaver.Engine"]

    /// True while recording.
    private(set) var isRunning = false
    /// Bumped whenever recorded data changes, so views re-read the summary.
    private(set) var revision = 0

    @ObservationIgnored private var accountant = UsageAccountant()
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var distributedObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var terminateObserver: NSObjectProtocol?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastFlush = Date.distantPast
    @ObservationIgnored private var currentDay: UsageDay?
    @ObservationIgnored private var observingSettings = false
    @ObservationIgnored private let store = UsageStore.shared

    private init() {}

    private var settings: UsageWidgetSettings { SettingsStore[.usageWidgetSettings] }
    private var calendar: Calendar { .current }

    // MARK: Lifecycle

    /// Called at launch (UsageStartup): starts recording if it is turned on, and follows the setting.
    func startIfEnabled() {
        observeSettings()
        applySettings()
    }

    private func observeSettings() {
        guard !observingSettings else { return }
        observingSettings = true
        withObservationTracking {
            _ = SettingsStore.shared.observedValue(.usageWidgetSettings)
        } onChange: {
            Task { @MainActor in
                let tracker = UsageTracker.shared
                tracker.observingSettings = false
                tracker.applySettings()
                tracker.observeSettings()
            }
        }
    }

    private func applySettings() {
        let s = settings
        if s.trackingEnabled {
            start()
            if accountant.excludedAppIDs != s.excludedSet {
                accountant.excludedAppIDs = s.excludedSet
                // closes the current app's slice if it was just excluded (or resumes it)
                handle(.flush(at: Date(), lastInputAt: Self.lastInputDate()))
                revision += 1
            }
        } else {
            stop()
        }
    }

    private func start() {
        guard !isRunning else { return }
        isRunning = true
        let now = Date()
        accountant = UsageAccountant(excludedAppIDs: settings.excludedSet, maximumGap: Self.maximumGap,
                                     startsLocked: Self.screenIsLocked())
        currentDay = UsageDay(now, calendar: calendar)
        store.prune(today: UsageDay(now, calendar: calendar), calendar: calendar)
        store.save()

        let ws = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated { UsageTracker.shared.activate(app) }
            },
            ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    let tracker = UsageTracker.shared
                    tracker.handle(.sleep(at: Date()))
                    tracker.persist()
                }
            },
            ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    let tracker = UsageTracker.shared
                    tracker.handle(.wake(at: Date()))
                    tracker.activate(NSWorkspace.shared.frontmostApplication)
                }
            },
            ws.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    let tracker = UsageTracker.shared
                    tracker.handle(.lock(at: Date()))
                    tracker.persist()
                }
            },
            ws.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { UsageTracker.shared.unlocked() }
            },
        ]
        let dnc = DistributedNotificationCenter.default()
        distributedObservers = [
            dnc.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    let tracker = UsageTracker.shared
                    tracker.handle(.lock(at: Date()))
                    tracker.persist()
                }
            },
            dnc.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { UsageTracker.shared.unlocked() }
            },
        ]
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { UsageTracker.shared.stop() }
        }

        activate(NSWorkspace.shared.frontmostApplication)
        lastFlush = now
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { _ in
            MainActor.assumeIsolated { UsageTracker.shared.tick() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        revision += 1
        NSLog("[Usage] tracking started")
    }

    private func stop() {
        guard isRunning else { return }
        handle(.stop(at: Date()))
        store.save()
        let ws = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { ws.removeObserver($0) }
        workspaceObservers = []
        distributedObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        distributedObservers = []
        if let terminateObserver { NotificationCenter.default.removeObserver(terminateObserver) }
        terminateObserver = nil
        timer?.invalidate()
        timer = nil
        isRunning = false
        revision += 1
        NSLog("[Usage] tracking stopped")
    }

    // MARK: Events

    private func activate(_ app: NSRunningApplication?) {
        let (id, name) = Self.identity(of: app)
        handle(.activate(appID: id, name: name, at: Date()))
    }

    private func unlocked() {
        handle(.unlock(at: Date()))
        activate(NSWorkspace.shared.frontmostApplication)
        persist()
    }

    private func tick() {
        let now = Date()
        let lastInput = Self.lastInputDate(now: now)
        let idleFor = now.timeIntervalSince(lastInput)
        if idleFor >= TimeInterval(max(settings.idleThreshold, 30)) {
            if !accountant.isIdle { handle(.idle(since: lastInput)) }
        } else if accountant.isIdle {
            handle(.active(at: lastInput))
        }
        let today = UsageDay(now, calendar: calendar)
        if today != currentDay {
            currentDay = today
            store.prune(today: today, calendar: calendar)
            lastFlush = .distantPast
        }
        if now.timeIntervalSince(lastFlush) >= Self.flushInterval {
            handle(.flush(at: now, lastInputAt: lastInput))
            persist()
        }
    }

    private func handle(_ event: UsageEvent) {
        guard isRunning else { return }
        let out = accountant.handle(event)
        guard !out.isEmpty else { return }
        let calendar = self.calendar
        for slice in out.slices {
            for part in UsageApportioner.split(slice, calendar: calendar) {
                store.add(seconds: part.seconds, appID: slice.appID, appName: slice.appName, day: part.day)
            }
        }
        for pickup in out.pickups {
            store.addPickup(day: UsageDay(pickup, calendar: calendar))
        }
    }

    private func persist() {
        lastFlush = Date()
        store.save()
        revision += 1
    }

    // MARK: Reading

    /// What the widget shows: the stored totals plus the open (not yet stored) slice.
    func summary(at now: Date = Date()) -> UsageSummary {
        let calendar = self.calendar
        var rows = store.rows
        if isRunning, let pending = accountant.pendingSlice(at: now) {
            for part in UsageApportioner.split(pending, calendar: calendar) {
                rows.append(UsageDailyRow(day: part.day, appID: pending.appID, appName: pending.appName, seconds: part.seconds))
            }
        }
        return UsageSummary.build(rows: rows, pickups: store.pickups, today: UsageDay(now, calendar: calendar),
                                  excludedAppIDs: settings.excludedSet, calendar: calendar)
    }

    /// Apps recorded in the last 7 days (for "exclude" suggestions), most used first.
    func recentApps(now: Date = Date()) -> [UsageAppTotal] {
        let calendar = self.calendar
        let since = UsageDay(now, calendar: calendar).adding(days: -6, calendar: calendar)
        var totals: [String: UsageAppTotal] = [:]
        for row in store.rows where row.day >= since {
            totals[row.appID, default: UsageAppTotal(appID: row.appID, appName: row.appName, seconds: 0)].seconds += row.seconds
        }
        return totals.values.sorted { $0.seconds > $1.seconds }
    }

    /// Writes the pending slice and saves (before an export, so the file includes the last seconds).
    func flushNow() {
        guard isRunning else { return }
        handle(.flush(at: Date()))
        persist()
    }

    func clearAllData() {
        flushNow()
        store.clearAll()
        revision += 1
    }

    func csv() -> String {
        flushNow()
        return UsageCSV.make(rows: store.rows, pickups: store.pickups)
    }

    #if DEBUG
    /// `usagelog`: the accountant's state.
    var debugState: String {
        let idleFor = Date().timeIntervalSince(Self.lastInputDate())
        return "frontmost=\(accountant.frontmostID ?? "nil") counting=\(accountant.isCounting) idle=\(accountant.isIdle) "
            + "asleep=\(accountant.isAsleep) locked=\(accountant.isLocked) lastInput=\(Int(idleFor))s ago"
    }
    #endif

    // MARK: System state

    static func identity(of app: NSRunningApplication?) -> (String?, String) {
        guard let app else { return (nil, "") }
        guard let id = app.bundleIdentifier ?? app.executableURL?.lastPathComponent,
              !ignoredAppIDs.contains(id) else { return (nil, "") }
        return (id, app.localizedName ?? id)
    }

    /// Time of the last keyboard / mouse / trackpad / tablet input in this login session.
    static func lastInputDate(now: Date = Date()) -> Date {
        // kCGAnyInputEventType (~0)
        guard let any = CGEventType(rawValue: ~0) else { return now }
        let seconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
        guard seconds.isFinite, seconds >= 0 else { return now }
        return now.addingTimeInterval(-seconds)
    }

    static func screenIsLocked() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (dict["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }
}

/// Launch hook (AppDelegate.applicationDidFinishLaunching): starts UsageTracker when tracking is on.
enum UsageStartup {
    @MainActor static func applicationDidFinishLaunching() {
        UsageTracker.shared.startIfEnabled()
    }
}

/// App icons by bundle identifier for the widget rows (cached; nil for apps that are no longer
/// installed). The settings pane uses SettingsAppIcon.
@MainActor
enum UsageAppIcons {
    private static var cache: [String: NSImage?] = [:]

    static func icon(for appID: String) -> NSImage? {
        if let cached = cache[appID] { return cached }
        let icon = SettingsApps.url(of: appID).map { NSWorkspace.shared.icon(forFile: $0.path) }
        cache[appID] = icon
        return icon
    }
}
