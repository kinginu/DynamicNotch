// Keep Awake (2026-10-20): holds an IOKit power assertion while the widget is on.
//
//   - display + system awake: kIOPMAssertionTypePreventUserIdleDisplaySleep (also prevents idle
//     system sleep); "Allow display to sleep": kIOPMAssertionTypePreventUserIdleSystemSleep only.
//   - timed sessions also pass the remaining time as the assertion's own timeout (action: release),
//     so the assertion ends on time even if the app's timer fires late; the app's timer then clears
//     the session and the live activity.
//   - the assertion is released when the session ends, is turned off, and on app quit (the kernel
//     would release it at process exit anyway). The session (end time) is persisted in UserDefaults
//     ("keepAwakeSession") and resumed at launch when `resumeAfterRelaunch` is on and it has not
//     expired and Keep Awake is still in the Nook.
//   - removing the widget from the Nook ends the session (its switch is the only control besides
//     Settings; the closed-notch activity is display-only).
//   - if the assertion cannot be created, the session is not started (the switch stays off).
//   - while active (and `showInClosedNotch`), requests the `.keepAwake` closed-notch live activity.
import Foundation
import AppKit
import IOKit.pwr_mgt
import Observation

@MainActor
@Observable
final class KeepAwakeManager {
    static let shared = KeepAwakeManager()

    /// The running session, nil while off.
    private(set) var session: Session?
    /// The assertion currently held allows the display to sleep (system-only assertion).
    private(set) var holdsSystemOnlyAssertion = false
    /// Last IOKit error (nil = fine).
    private(set) var lastError: String?

    struct Session: Codable, Equatable {
        var duration: KeepAwakeDuration
        var started: Date
        /// nil = until turned off.
        var endDate: Date?
    }

    var isActive: Bool { session != nil }

    @ObservationIgnored private var assertionID: IOPMAssertionID = IOPMAssertionID(kIOPMNullAssertionID)
    @ObservationIgnored private var endTimer: Timer?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var settingsTask: Task<Void, Never>?
    @ObservationIgnored private var nookTask: Task<Void, Never>?
    @ObservationIgnored private var settings = SettingsStore[.keepAwakeWidgetSettings]
    /// DEBUG `kalive`: a session that is never written to UserDefaults.
    @ObservationIgnored var persists = true

    static let sessionDefaultsKey = "keepAwakeSession"

    private init() {}

    // MARK: lifecycle

    /// Called once at launch (LiveActivitiesStartup): resume a persisted session, follow settings.
    func start() {
        guard !started else { return }
        started = true
        #if DEBUG
        KeepAwakeDebugHooks.install()
        #endif

        if let saved = Self.loadSession() {
            if settings.resumeAfterRelaunch, Self.widgetInNook,
               saved.endDate.map({ $0 > Date().addingTimeInterval(1) }) ?? true {
                begin(saved)
            } else {
                Self.saveSession(nil)
            }
        }

        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                let mgr = KeepAwakeManager.shared
                mgr.releaseAssertion()
                if !mgr.settings.resumeAfterRelaunch { Self.saveSession(nil) }
            }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { KeepAwakeManager.shared.checkExpiry() }
        })
        settingsTask = Task { @MainActor in
            for await value in SettingsStore.updates(.keepAwakeWidgetSettings, initial: false) {
                KeepAwakeManager.shared.apply(settings: value)
            }
        }
        // the widget left the Nook: end its session (nothing else would turn the assertion off)
        nookTask = Task { @MainActor in
            for await nook in SettingsStore.updates(.nookSettings, initial: true) {
                if !nook.widgets.contains(.keepAwake), KeepAwakeManager.shared.isActive {
                    KeepAwakeManager.shared.deactivate()
                }
            }
        }
    }

    private static var widgetInNook: Bool { SettingsStore[.nookSettings].widgets.contains(.keepAwake) }

    // MARK: control

    /// Start (or restart) a session of `duration`; remembers it as the switch's duration.
    func activate(_ duration: KeepAwakeDuration) {
        if SettingsStore[.keepAwakeWidgetSettings].lastDuration != duration {
            SettingsStore[.keepAwakeWidgetSettings].lastDuration = duration
        }
        let now = Date()
        begin(Session(duration: duration, started: now, endDate: duration.seconds.map { now.addingTimeInterval($0) }))
    }

    func deactivate() {
        endTimer?.invalidate()
        endTimer = nil
        releaseAssertion()
        if session != nil { session = nil }
        if persists { Self.saveSession(nil) }
        persists = true
        syncLiveActivity()
    }

    func toggle() {
        if isActive { deactivate() } else { activate(SettingsStore[.keepAwakeWidgetSettings].lastDuration) }
    }

    /// Seconds left (nil while off or for "until turned off").
    func remaining(at date: Date = Date()) -> TimeInterval? {
        guard let end = session?.endDate else { return nil }
        return max(0, end.timeIntervalSince(date))
    }

    // MARK: internals

    private func begin(_ new: Session) {
        session = new
        guard holdAssertion() else {
            // no assertion: do not show a session that would not keep the Mac awake
            endTimer?.invalidate()
            endTimer = nil
            releaseAssertion()
            session = nil
            if persists { Self.saveSession(nil) }
            syncLiveActivity()
            return
        }
        if persists { Self.saveSession(new) }
        endTimer?.invalidate()
        endTimer = nil
        if let end = new.endDate {
            let timer = Timer(fire: end, interval: 0, repeats: false) { _ in
                MainActor.assumeIsolated { KeepAwakeManager.shared.checkExpiry() }
            }
            timer.tolerance = 0.5
            RunLoop.main.add(timer, forMode: .common)
            endTimer = timer
        }
        syncLiveActivity()
    }

    private func checkExpiry() {
        guard let end = session?.endDate else { return }
        if end <= Date().addingTimeInterval(0.5) { deactivate() }
    }

    private func apply(settings value: KeepAwakeWidgetSettings) {
        let old = settings
        settings = value
        if isActive, old.allowDisplaySleep != value.allowDisplaySleep { holdAssertion() }
        if old.showInClosedNotch != value.showInClosedNotch { syncLiveActivity() }
    }

    /// Create the assertion for the current session and settings (replacing any previous one; the new
    /// one is created first so there is no gap). False when IOKit refused the new assertion (any
    /// previous one is still held then).
    @discardableResult
    private func holdAssertion() -> Bool {
        guard let session else { releaseAssertion(); return false }
        let systemOnly = settings.allowDisplaySleep
        let type = (systemOnly ? kIOPMAssertionTypePreventUserIdleSystemSleep : kIOPMAssertionTypePreventUserIdleDisplaySleep) as CFString
        let name = "DynamicNotch Keep Awake" as CFString
        let details: CFString = (session.endDate.map {
            "Keep Awake widget, until \(DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short))"
        } ?? "Keep Awake widget, until turned off") as CFString
        let timeout: CFTimeInterval = session.endDate.map { max(1, $0.timeIntervalSinceNow) } ?? 0
        var newID = IOPMAssertionID(kIOPMNullAssertionID)
        let result = IOPMAssertionCreateWithDescription(
            type, name, details, nil, nil, timeout,
            timeout > 0 ? (kIOPMAssertionTimeoutActionRelease as CFString) : nil,
            &newID)
        guard result == kIOReturnSuccess else {
            lastError = String(format: "IOPMAssertionCreateWithDescription failed (0x%08x)", result)
            NSLog("[KeepAwake] %@", lastError ?? "")
            return false
        }
        releaseAssertion()
        assertionID = newID
        holdsSystemOnlyAssertion = systemOnly
        if lastError != nil { lastError = nil }
        return true
    }

    private func releaseAssertion() {
        guard assertionID != IOPMAssertionID(kIOPMNullAssertionID) else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = IOPMAssertionID(kIOPMNullAssertionID)
    }

    private func syncLiveActivity() {
        let show = isActive && settings.showInClosedNotch
        if show { ActiveLiveActivitiesManager.shared.insertSync(.keepAwake) }
        else { ActiveLiveActivitiesManager.shared.removeSync(.keepAwake) }
    }

    // MARK: persistence

    private static func loadSession() -> Session? {
        guard let data = UserDefaults.standard.data(forKey: sessionDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    private static func saveSession(_ session: Session?) {
        if let session, let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: sessionDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: sessionDefaultsKey)
        }
    }

    #if DEBUG
    /// DEBUG: whether an assertion is held right now.
    var debugAssertionID: IOPMAssertionID { assertionID }
    /// DEBUG (`kalive`): start an arbitrary session.
    func debugStart(_ session: Session) { begin(session) }
    #endif
}

/// Countdown text shared by the widget and the live activity: "14:05", "1:59:59".
enum KeepAwakeFormat {
    static func countdown(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}
