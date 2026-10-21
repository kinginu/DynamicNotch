// Next Up widget model (2026-10-20): the next upcoming calendar events, their meeting links,
// and the closed-notch "starts in 5 min" live activity (`LiveActivity.nextUp`).
//
// Access and the event store come from CalendarManager.shared (`hasReadAccess`, `eventStore`,
// `requestFullAccess()`). The widget has its own calendar selection (NextUpWidgetSettings), which
// differs from the Calendar widget's, so it does not read CalendarManager's per-day cache: it runs
// ONE EventKit query for [now − 1 day, now + lookahead] on a background queue, at start, every
// minute, after EKEventStoreChanged (coalesced) and when its settings change. Rows are plain values
// (no EKEvent reaches the views). All of this — the queries, the timers and the closed-notch
// activity — runs only while the Next Up widget is in the Nook (WidgetPresence); the
// activity timer additionally needs `showLiveActivity`. Removing the widget clears the activity.
import AppKit
import EventKit
import Observation
import SwiftUI

/// One upcoming (or in-progress) event, as shown by the widget.
struct NextUpItem: Identifiable, Equatable {
    /// Event identifier + start (recurring occurrences share the event identifier).
    var id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var location: String?
    var calendarTitle: String
    var color: Color
    var meeting: NextUpMeetingLink?

    func isInProgress(at now: Date) -> Bool { start <= now && now < end }
}

/// A video-call link found in an event's URL, location or notes.
struct NextUpMeetingLink: Equatable {
    enum Service: String, Equatable {
        case zoom, meet, teams, webex, facetime

        var displayName: String {
            switch self {
            case .zoom: return "Zoom"
            case .meet: return "Google Meet"
            case .teams: return "Microsoft Teams"
            case .webex: return "Webex"
            case .facetime: return "FaceTime"
            }
        }
    }

    var url: URL
    var service: Service

    /// Brand hosts are matched as the whole host or a dot-separated suffix (us02web.zoom.us, not
    /// evilzoom.us), so a lookalike domain never gets a "Join Zoom" button.
    private static let patterns: [(Service, NSRegularExpression)] = {
        let tail = #"[^\s<>"'()\[\]{}]*"#
        let raw: [(Service, String)] = [
            (.zoom, #"(?:https?://(?:[\w-]+\.)*zoom\.(?:us|com)/(?:j|my|s|w|wc)/"# + tail + #"|zoommtg://"# + tail + ")"),
            (.meet, #"https?://meet\.google\.com/[a-z0-9-]+"# + tail),
            (.teams, #"https?://teams\.(?:microsoft|live)\.com/"# + tail),
            (.webex, #"https?://(?:[\w-]+\.)*webex\.com/"# + tail),
            (.facetime, #"https?://facetime\.apple\.com/join"# + tail),
        ]
        return raw.compactMap { service, pattern in
            (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])).map { (service, $0) }
        }
    }()

    /// First meeting link in `texts` (searched in order: the event URL, location, notes).
    static func find(in texts: [String?]) -> NextUpMeetingLink? {
        for case let text? in texts where !text.isEmpty {
            let range = NSRange(text.startIndex..., in: text)
            var best: (offset: Int, link: NextUpMeetingLink)?
            for (service, regex) in patterns {
                guard let m = regex.firstMatch(in: text, range: range), let r = Range(m.range, in: text) else { continue }
                var s = String(text[r])
                while let last = s.last, ".,;:!?".contains(last) { s.removeLast() }
                guard let url = URL(string: s) else { continue }
                if best == nil || m.range.location < best!.offset {
                    best = (m.range.location, NextUpMeetingLink(url: url, service: service))
                }
            }
            if let best { return best.link }
        }
        return nil
    }

    /// Opens the link in the default web browser (an app scheme such as zoommtg:// goes to its app).
    func open() {
        let workspace = NSWorkspace.shared
        if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
           let probe = URL(string: "https://example.com"),
           let browser = workspace.urlForApplication(toOpen: probe) {
            workspace.open([url], withApplicationAt: browser, configuration: NSWorkspace.OpenConfiguration())
        } else {
            workspace.open(url)
        }
    }
}

@MainActor
@Observable
final class NextUpManager {
    static let shared = NextUpManager()

    /// Every not-yet-ended event in the window, sorted by start (the widget shows `maxEvents`).
    private(set) var items: [NextUpItem] = []
    /// The event the closed-notch activity is about (nil = no activity).
    private(set) var activityItem: NextUpItem? = nil
    private(set) var isLoading = false
    private(set) var settings = SettingsStore[.nextUpWidgetSettings]

    @ObservationIgnored private var started = false
    @ObservationIgnored private var refreshTimer: Timer?
    @ObservationIgnored private var activityTimer: Timer?
    @ObservationIgnored private var storeObserver: NSObjectProtocol?
    @ObservationIgnored private var storeChangeWork: DispatchWorkItem?
    @ObservationIgnored private var settingsTask: Task<Void, Never>?
    /// The queries / timers run only while the widget is in the Nook (no view counts: the
    /// closed-notch activity needs them with no view on screen).
    @ObservationIgnored private lazy var presence: WidgetPresence = {
        let presence = WidgetPresence(.nextUp, label: "NextUp",
                                      onNeeded: { [unowned self] in self.install() },
                                      onIdle: { [unowned self] in self.tearDown() })
        #if DEBUG
        presence.debugIsRunning = { [unowned self] in
            self.refreshTimer != nil || self.activityTimer != nil || self.storeObserver != nil
        }
        #endif
        return presence
    }()
    @ObservationIgnored private var generation = 0
    /// Activities the user dismissed (`NextUpItem.id`); pruned when the event is gone.
    @ObservationIgnored private var dismissed: Set<String> = []
    #if DEBUG
    /// DEBUG hook `nextup:force`: a synthetic activity, kept until `nextup:clear`.
    @ObservationIgnored var debugActivity: NextUpItem? = nil
    #endif

    private let fetchQueue = DispatchQueue(label: "DynamicNotch.NextUp.fetch", qos: .utility)

    private var calendarManager: CalendarManager { .shared }
    var hasAccess: Bool { calendarManager.hasReadAccess }

    /// The Next Up widget is in the Nook.
    private var isInNook: Bool { presence.isInNook }

    /// Called once at launch (LiveActivitiesStartup) so the activity works with the notch closed.
    /// Only watches the settings and the layout; the presence runs the queries / timers while the
    /// widget is in the Nook.
    func start() {
        guard !started else { return }
        started = true
        #if DEBUG
        NextUpDebug.install()
        #endif
        settingsTask = Task { @MainActor in
            for await value in SettingsStore.updates(.nextUpWidgetSettings, initial: false) {
                NextUpManager.shared.settings = value
                NextUpManager.shared.reconcileActivity()
                NextUpManager.shared.refresh()
            }
        }
        presence.onLayoutChange = { [unowned self] in self.reconcileActivity() }
        presence.activate()
        reconcileActivity()
    }

    /// The widget is in the Nook: the EventKit observer and the minute tick.
    private func install() {
        guard refreshTimer == nil else { return }
        storeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: calendarManager.eventStore, queue: .main
        ) { _ in
            MainActor.assumeIsolated { NextUpManager.shared.scheduleStoreRefresh() }
        }
        let refreshTick = Timer(timeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated {
                NextUpManager.shared.presence.debugCheckTick("refresh timer")
                NextUpManager.shared.refresh()
            }
        }
        refreshTick.tolerance = 10
        RunLoop.main.add(refreshTick, forMode: .common)
        refreshTimer = refreshTick
        refresh()
        reconcileActivity()
    }

    /// The widget left the Nook: removes everything and clears the items / activity.
    private func tearDown() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        if let storeObserver { NotificationCenter.default.removeObserver(storeObserver) }
        storeObserver = nil
        storeChangeWork?.cancel()
        storeChangeWork = nil
        generation += 1 // drop an in-flight fetch
        isLoading = false
        if !items.isEmpty { items = [] }
        dismissed.removeAll()
        reconcileActivity()
    }

    /// Installs or removes the 10 s activity tick: needs the widget in the Nook and `showLiveActivity`.
    private func reconcileActivity() {
        let wantsActivity = presence.isActive && settings.showLiveActivity
        if wantsActivity, activityTimer == nil {
            let activity = Timer(timeInterval: 10, repeats: true) { _ in
                MainActor.assumeIsolated {
                    NextUpManager.shared.presence.debugCheckTick("activity timer")
                    NextUpManager.shared.evaluateActivity()
                }
            }
            activity.tolerance = 2
            RunLoop.main.add(activity, forMode: .common)
            activityTimer = activity
        } else if !wantsActivity, activityTimer != nil {
            activityTimer?.invalidate()
            activityTimer = nil
        }
        evaluateActivity()
    }

    private func scheduleStoreRefresh() {
        storeChangeWork?.cancel()
        let work = DispatchWorkItem { NextUpManager.shared.refresh() }
        storeChangeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// Re-queries EventKit off the main thread.
    func refresh() {
        guard hasAccess, isInNook else {
            if !items.isEmpty { items = [] }
            evaluateActivity()
            return
        }
        generation += 1
        let token = generation
        let settings = settings
        let store = UncheckedBox(value: calendarManager.eventStore)
        isLoading = items.isEmpty
        fetchQueue.async {
            let fetched = Self.fetch(store: store.value, settings: settings, now: Date())
            let box = UncheckedBox(value: fetched)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let manager = NextUpManager.shared
                    guard token == manager.generation else { return }
                    manager.isLoading = false
                    if box.value != manager.items { manager.items = box.value }
                    manager.dismissed.formIntersection(box.value.map(\.id))
                    manager.evaluateActivity()
                }
            }
        }
    }

    nonisolated private static func fetch(store: EKEventStore, settings: NextUpWidgetSettings, now: Date) -> [NextUpItem] {
        let excluded = Set(settings.excludedCalendarIDs)
        let calendars = store.calendars(for: .event).filter { !excluded.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }
        let start = now.addingTimeInterval(-24 * 3600) // in-progress events that started earlier
        let end = now.addingTimeInterval(TimeInterval(max(1, settings.lookaheadHours)) * 3600)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate)
            .filter { event in
                guard let s = event.startDate, let e = event.endDate, e > now, s < end else { return false }
                if event.status == .canceled { return false }
                if event.isAllDay && !settings.includeAllDay { return false }
                if let me = event.attendees?.first(where: \.isCurrentUser), me.participantStatus == .declined { return false }
                return true
            }
            .sorted { a, b in
                if a.isAllDay != b.isAllDay { return !a.isAllDay } // timed events first
                return (a.startDate ?? .distantPast) < (b.startDate ?? .distantPast)
            }
            .prefix(20)
            .map { event in
                let s = event.startDate ?? now
                let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines)
                return NextUpItem(
                    id: "\(event.eventIdentifier ?? event.calendarItemIdentifier)@\(Int(s.timeIntervalSince1970))",
                    title: (event.title?.isEmpty == false ? event.title! : String(localized: "New Event")),
                    start: s,
                    end: event.endDate ?? s,
                    isAllDay: event.isAllDay,
                    location: location?.isEmpty == false ? location : nil,
                    calendarTitle: event.calendar?.title ?? "",
                    color: event.calendar.map { Color(nsColor: $0.color) } ?? .accentColor,
                    meeting: NextUpMeetingLink.find(in: [event.url?.absoluteString, event.location, event.notes])
                )
            }
    }

    /// Rows shown by the widget (ended events dropped as time passes).
    func visibleItems(at now: Date) -> [NextUpItem] {
        Array(items.filter { $0.end > now }.prefix(min(3, max(1, settings.maxEvents))))
    }

    // MARK: - Live activity

    /// Shows `.nextUp` from `leadMinutes` before a timed event until 2 min after its start.
    func evaluateActivity(now: Date = Date()) {
        var next: NextUpItem? = nil
        if settings.showLiveActivity, hasAccess, isInNook {
            let lead = TimeInterval(max(1, settings.leadMinutes) * 60)
            next = items.first { item in
                !item.isAllDay && !dismissed.contains(item.id)
                    && now >= item.start.addingTimeInterval(-lead)
                    && now < min(item.end, item.start.addingTimeInterval(120))
            }
        }
        #if DEBUG
        if let debugActivity { next = debugActivity }
        #endif
        if next != activityItem { activityItem = next }
        let manager = ActiveLiveActivitiesManager.shared
        if next != nil { manager.insertSync(.nextUp) } else { manager.removeSync(.nextUp) }
    }

    /// Hides the closed-notch activity for the current event (it comes back for the next one).
    func dismissActivity() {
        guard let item = activityItem else { return }
        #if DEBUG
        debugActivity = nil
        #endif
        dismissed.insert(item.id)
        evaluateActivity()
    }

    #if DEBUG
    func debugSetActivity(_ item: NextUpItem?) {
        debugActivity = item
        evaluateActivity()
    }
    #endif
}

/// EventKit objects cross to the fetch queue (EKEventStore reads are thread-safe).
private struct UncheckedBox<T>: @unchecked Sendable { let value: T }

// MARK: - Text

enum NextUpFormat {
    /// "in 12 min", "in 2 h 5 min", "tomorrow, 09:00", "now · 23 min left", "all day".
    static func countdown(for item: NextUpItem, now: Date) -> String {
        if item.isAllDay {
            let calendar = Calendar.current
            if calendar.isDateInToday(item.start) || item.start <= now { return String(localized: "All day") }
            if calendar.isDateInTomorrow(item.start) { return String(localized: "Tomorrow, all day") }
            let weekday = item.start.formatted(.dateTime.weekday(.abbreviated))
            return String(localized: "\(weekday), all day")
        }
        if item.isInProgress(at: now) {
            let left = Int(ceil(item.end.timeIntervalSince(now) / 60))
            if left < 60 { return String(localized: "now · \(left) min left") }
            let h = left / 60, m = left % 60
            return m == 0 ? String(localized: "now · \(h) h left") : String(localized: "now · \(h) h \(m) min left")
        }
        let minutes = Int(ceil(item.start.timeIntervalSince(now) / 60))
        if minutes < 60 { return String(localized: "in \(max(1, minutes)) min") }
        if minutes < 12 * 60 {
            let h = minutes / 60, m = minutes % 60
            return m == 0 ? String(localized: "in \(h) h") : String(localized: "in \(h) h \(m) min")
        }
        let time = item.start.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInTomorrow(item.start) { return String(localized: "tomorrow, \(time)") }
        if Calendar.current.isDateInToday(item.start) { return String(localized: "today, \(time)") }
        return item.start.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    /// "14:00 – 14:30".
    static func timeRange(for item: NextUpItem) -> String {
        if item.isAllDay { return String(localized: "All day") }
        return "\(item.start.formatted(date: .omitted, time: .shortened)) – \(item.end.formatted(date: .omitted, time: .shortened))"
    }

    /// Closed-notch trailing text: "5 min", "Now".
    static func compact(until start: Date, now: Date) -> String {
        let minutes = Int(ceil(start.timeIntervalSince(now) / 60))
        if minutes <= 0 { return String(localized: "Now") }
        return String(localized: "\(minutes) min")
    }
}
