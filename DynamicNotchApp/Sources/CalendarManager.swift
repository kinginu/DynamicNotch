// CalendarManager — EventKit access for the Calendar widget, the Next Up widget and the calendar
// live activity.
//
// Owns the app's `EKEventStore`, the calendar-access state and the user's calendar selection
// (persisted in `UserDefaults.standard.calendarWidgetSettings`). Publishes today's events
// (`events`, read by LiveActivityCenter) and serves per-day event lists to the Calendar widget
// from a per-week cache: a cache miss costs one EventKit query for the whole week, and the
// neighbouring weeks are prefetched off the main thread. Store changes are coalesced.
import AppKit
import EventKit
import Observation
import os

private let logger = Logger(subsystem: "com.example.dynamicnotch.DynamicNotch", category: "calendar")

@MainActor
@Observable
final class CalendarManager {
    static let shared = CalendarManager()

    /// Today's events from the selected calendars, after the widget's filters.
    private(set) var events: [EKEvent] = []

    /// Calendar access as last read from EventKit (`refreshAuthorizationStatus()` re-reads it).
    var authorizationStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)

    /// Calendars shown by the widgets. Empty means "all calendars" unless the user deselected every
    /// calendar (`selectionIsExplicitlyEmpty`: then nothing is shown).
    var selectedCalendars: [EKCalendar] = [] {
        didSet { invalidateDayCache() }
    }

    /// Bumped after every coalesced refresh (store change, midnight, selection change, access
    /// granted): views that cache per-day lists (Calendar widget) reload on it, so edited events
    /// show up even when today's event count stays the same.
    private(set) var revision = 0

    let eventStore = EKEventStore()

    // MARK: Private state

    @ObservationIgnored private let fetchQueue = DispatchQueue(label: "DynamicNotch.CalendarManager.fetch", qos: .userInitiated)
    /// Events per day (start of day) for every fetched week, valid for `dayCacheSignature`.
    @ObservationIgnored private var dayCache: [Date: [EKEvent]] = [:]
    @ObservationIgnored private var cachedWeeks: Set<Date> = []
    @ObservationIgnored private var weeksInFlight: Set<Date> = []
    @ObservationIgnored private var dayCacheSignature = ""
    /// Bumped on every invalidation so that fetches started before it are dropped.
    @ObservationIgnored private var dayCacheGeneration = 0
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    // App-lifetime singleton: the observers and the refresh task are never torn down.
    private init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .EKEventStoreChanged, object: eventStore, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.storeChanged() }
        })
        // midnight (also posted after waking past midnight): "today" changed
        observers.append(center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.invalidateDayCache()
                self?.scheduleRefresh()
            }
        })
        // access granted / revoked outside the widgets (Settings ▸ Permissions, System Settings):
        // PermissionCenter publishes the change (it re-reads on activation and while polling); the
        // activation observer covers the case where PermissionCenter was never created
        observers.append(center.addObserver(forName: PermissionCenter.didChangeNotification, object: nil, queue: .main) { [weak self] note in
            guard (note.userInfo?["permission"] as? AppPermission) == .calendar else { return }
            MainActor.assumeIsolated { self?.refreshAuthorizationStatus() }
        })
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAuthorizationStatus() }
        })
        if hasReadAccess {
            loadSelectedCalendars()
        }
        scheduleRefresh()
    }

    // MARK: - Access

    /// True when events can be read (full access).
    var hasReadAccess: Bool { authorizationStatus == .fullAccess }

    /// Re-reads the authorization status (e.g. after the user changed it in System Settings); when
    /// access was just granted (or revoked) loads the selection and refetches today's events, so
    /// the widgets, Next Up and the calendar live activity recover without waiting for a store
    /// change or midnight.
    func refreshAuthorizationStatus() {
        let wasGranted = hasReadAccess
        let status = EKEventStore.authorizationStatus(for: .event)
        if status != authorizationStatus {
            authorizationStatus = status
        }
        if hasReadAccess && selectedCalendars.isEmpty && !selectionIsExplicitlyEmpty {
            loadSelectedCalendars()
        }
        if hasReadAccess != wasGranted {
            if !hasReadAccess { selectedCalendars = [] }
            invalidateDayCache()
            scheduleRefresh()
            NextUpManager.shared.refresh()
        }
    }

    /// Asks for full calendar access (shows the system prompt once; afterwards the user must
    /// change it in System Settings ▸ Privacy & Security ▸ Calendars).
    func requestFullAccess() async {
        let error: (any Error)? = await withCheckedContinuation { continuation in
            eventStore.requestFullAccessToEvents { _, error in continuation.resume(returning: error) }
        }
        if let error {
            logger.error("calendar access request failed: \(String(describing: error), privacy: .public)")
        }
        refreshAuthorizationStatus()
        if hasReadAccess {
            await reloadEvents()
        }
    }

    /// Opens System Settings ▸ Privacy & Security ▸ Calendars (access was denied earlier).
    func requestAccessFromUser() async {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Calendar selection

    /// Restores the saved calendar selection: all calendars when nothing was saved, none when the
    /// user deselected every calendar.
    func loadSelectedCalendars() {
        guard hasReadAccess else {
            selectedCalendars = []
            return
        }
        var settings = UserDefaults.standard.calendarWidgetSettings
        let allCalendars = eventStore.calendars(for: .event)
        switch Self.savedSelection(settings) {
        case .all:
            selectedCalendars = allCalendars
        case .none:
            selectedCalendars = []
        case .some(let saved):
            let kept = allCalendars.filter { saved.contains($0.calendarIdentifier) }
            guard !kept.isEmpty else {
                // every saved calendar is gone (account removed / re-added): show all again
                selectedCalendars = allCalendars
                return
            }
            selectedCalendars = kept
            // drop identifiers of calendars that no longer exist
            settings.savedIdentifiers = kept.map(\.calendarIdentifier)
            UserDefaults.standard.calendarWidgetSettings = settings
        }
    }

    /// Selects `calendars`, saves the selection and refetches today's events. An empty selection
    /// is saved as "show none" (`selectionWasExplicit`), not read back as "all calendars".
    func updateSelectedCalendars(_ calendars: [EKCalendar]) {
        var settings = UserDefaults.standard.calendarWidgetSettings
        settings.savedIdentifiers = calendars.map(\.calendarIdentifier)
        settings.selectionWasExplicit = calendars.isEmpty
        UserDefaults.standard.calendarWidgetSettings = settings
        selectedCalendars = calendars
        scheduleRefresh()
    }

    /// What a stored selection means.
    enum SavedSelection: Equatable {
        /// Nothing chosen yet (or a legacy empty list): every calendar.
        case all
        /// The user deselected every calendar: no events.
        case none
        case some(Set<String>)
    }

    nonisolated static func savedSelection(_ settings: CalendarSelectionSettings) -> SavedSelection {
        guard let saved = settings.savedIdentifiers else { return .all }
        if saved.isEmpty { return settings.selectionWasExplicit ? .none : .all }
        return .some(Set(saved))
    }

    /// The user deselected every calendar: the fetches return nothing (EventKit would read an
    /// empty / nil calendar list as "all calendars").
    var selectionIsExplicitlyEmpty: Bool {
        selectedCalendars.isEmpty && Self.savedSelection(UserDefaults.standard.calendarWidgetSettings) == .none
    }

    // MARK: - Today's events

    /// Refetches today's events (coalesced: a newer call cancels a pending one).
    private func scheduleRefresh(after delay: Duration = .zero) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled, let self else { return }
            await self.reloadEvents()
            guard !Task.isCancelled else { return }
            self.revision &+= 1
            self.prefetchWeek()
        }
    }

    private func reloadEvents() async {
        guard hasReadAccess, !selectionIsExplicitlyEmpty else {
            if !events.isEmpty { events = [] }
            return
        }
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        guard let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) else { return }
        let predicate = eventStore.predicateForEvents(withStart: todayStart, end: tomorrowStart, calendars: calendarsForQuery)
        let request = EKUncheckedBox(value: (store: eventStore, predicate: predicate))
        let fetched = await onFetchQueue { EKUncheckedBox(value: request.value.store.events(matching: request.value.predicate)) }
        let filtered = Self.applyEventFilters(fetched.value, settings: UserDefaults.standard.calendarWidgetSettings)
        if filtered != events {
            events = filtered
        }
    }

    /// Today's-events filters:
    ///  - "Show all-day events" off: only events that start today and have not ended yet;
    ///  - events that span several days are kept only when they are timed and last 24 h or more.
    private static func applyEventFilters(_ events: [EKEvent], settings: CalendarSelectionSettings) -> [EKEvent] {
        let calendar = Calendar.current
        let now = Date()
        return events.filter { event in
            if !settings.showAllDayEvents {
                guard let start = event.startDate, calendar.isDateInToday(start),
                      let end = event.endDate, end > now else { return false }
            }
            guard event.isMultiDay, let start = event.startDate, let end = event.endDate else { return true }
            return !event.isAllDay && end.timeIntervalSince(start) >= 86_400
        }
    }

    private func storeChanged() {
        // a sync burst posts many notifications: drop the cache now, refetch once (300 ms later)
        invalidateDayCache()
        scheduleRefresh(after: .milliseconds(300))
    }

    // MARK: - Per-day lists (Calendar widget)

    /// Events of one day from the selected calendars, sorted (all-day first, then by start).
    /// Served from the per-week cache; on a miss the whole week is fetched with a single query,
    /// so a widget reload that asks for all seven weekdays costs at most one EventKit round trip
    /// — and none once `prefetchWeek(containing:)` has warmed the cache in the background.
    func events(on day: Date) -> [EKEvent] {
        guard hasReadAccess, !selectionIsExplicitlyEmpty else { return [] }
        let start = Calendar.current.startOfDay(for: day)
        let signature = currentDayCacheSignature()
        if dayCacheSignature == signature, let hit = dayCache[start] { return hit }
        guard let week = weekInterval(containing: start) else { return [] }
        let days = Self.fetchDays(store: eventStore, in: week, calendars: calendarsForQuery,
                                  showAllDay: UserDefaults.standard.calendarWidgetSettings.showAllDayEvents)
        storeWeek(days, week: week.start, signature: signature, generation: dayCacheGeneration)
        // warm the neighbouring weeks for the widget's week paging
        let calendar = Calendar.current
        if let previous = calendar.date(byAdding: .day, value: -7, to: week.start) { prefetchWeek(containing: previous) }
        if let next = calendar.date(byAdding: .day, value: 7, to: week.start) { prefetchWeek(containing: next) }
        return days[start] ?? []
    }

    /// Fills the cache for the week containing `day` off the main thread (no-op if cached).
    func prefetchWeek(containing day: Date = Date()) {
        guard hasReadAccess, !selectionIsExplicitlyEmpty, let week = weekInterval(containing: day) else { return }
        let signature = currentDayCacheSignature()
        let isCached = cachedWeeks.contains(week.start) && dayCacheSignature == signature
        guard !isCached, !weeksInFlight.contains(week.start) else { return }
        weeksInFlight.insert(week.start)
        let generation = dayCacheGeneration
        let showAllDay = UserDefaults.standard.calendarWidgetSettings.showAllDayEvents
        let request = EKUncheckedBox(value: (store: eventStore, calendars: calendarsForQuery))
        Task { [weak self] in
            guard let self else { return }
            let days = await self.onFetchQueue {
                EKUncheckedBox(value: Self.fetchDays(store: request.value.store, in: week,
                                                     calendars: request.value.calendars, showAllDay: showAllDay))
            }
            self.weeksInFlight.remove(week.start)
            self.storeWeek(days.value, week: week.start, signature: signature, generation: generation)
        }
    }

    /// Runs `work` on the serial fetch queue and returns its result to the caller's actor.
    private func onFetchQueue<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            fetchQueue.async { continuation.resume(returning: work()) }
        }
    }

    private var calendarsForQuery: [EKCalendar]? { selectedCalendars.isEmpty ? nil : selectedCalendars }

    private func invalidateDayCache() {
        dayCache = [:]
        cachedWeeks = []
        weeksInFlight = [] // their results are dropped (generation), so they may be refetched
        dayCacheGeneration += 1
    }

    /// Identifies what the cached lists depend on (selected calendars, all-day filter).
    private func currentDayCacheSignature() -> String {
        let showAllDay = UserDefaults.standard.calendarWidgetSettings.showAllDayEvents
        return selectedCalendars.map(\.calendarIdentifier).sorted().joined(separator: ",") + "|\(showAllDay)"
    }

    private func weekInterval(containing day: Date) -> DateInterval? {
        Calendar.current.dateInterval(of: .weekOfYear, for: day)
    }

    private func storeWeek(_ days: [Date: [EKEvent]], week: Date, signature: String, generation: Int) {
        guard generation == dayCacheGeneration else { return } // invalidated meanwhile
        if signature != dayCacheSignature {
            dayCache = [:]
            cachedWeeks = []
            dayCacheSignature = signature
        }
        dayCache.merge(days) { _, new in new }
        cachedWeeks.insert(week)
    }

    /// Runs one EventKit query for `interval` and buckets the (filtered, sorted) events per day.
    /// Thread-safe (EKEventStore reads may run on any thread).
    nonisolated private static func fetchDays(store: EKEventStore, in interval: DateInterval, calendars: [EKCalendar]?,
                                              showAllDay: Bool) -> [Date: [EKEvent]] {
        let calendar = Calendar.current
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: calendars)
        let all = store.events(matching: predicate).filter { showAllDay || !$0.isAllDay }
        var result: [Date: [EKEvent]] = [:]
        var day = interval.start
        while day < interval.end {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            result[day] = all
                .filter { event in
                    let start = event.startDate ?? .distantPast
                    let end = event.endDate ?? start
                    return start < next && (end > day || start >= day) // overlaps this day
                }
                .sorted { a, b in
                    if a.isAllDay != b.isAllDay { return a.isAllDay }
                    return (a.startDate ?? .distantPast) < (b.startDate ?? .distantPast)
                }
            day = next
        }
        return result
    }
}

// MARK: - Calendar selection settings

/// The Calendar widget's calendar selection and event filters, stored as JSON in
/// `UserDefaults.standard` under "calendarSelectionSettings" (separate from the
/// `calendarWidgetSettings` stored setting, which holds the widget's layout prefs).
struct CalendarSelectionSettings: Codable, Sendable {
    var savedIdentifiers: [String]?
    var selectionWasExplicit: Bool = false
    var showAllDayEvents: Bool = true
    var showMultiDayEvents: Bool = true
}

extension UserDefaults {
    private static let calendarSelectionSettingsKey = "calendarSelectionSettings"

    var calendarWidgetSettings: CalendarSelectionSettings {
        get {
            guard let data = data(forKey: Self.calendarSelectionSettingsKey) else { return CalendarSelectionSettings() }
            do {
                return try JSONDecoder().decode(CalendarSelectionSettings.self, from: data)
            } catch {
                logger.error("calendar selection settings unreadable, using defaults: \(String(describing: error), privacy: .public)")
                return CalendarSelectionSettings()
            }
        }
        set {
            do {
                set(try JSONEncoder().encode(newValue), forKey: Self.calendarSelectionSettingsKey)
            } catch {
                logger.error("calendar selection settings not saved: \(String(describing: error), privacy: .public)")
            }
        }
    }
}

extension EKEvent {
    /// True when the event starts and ends on different days.
    var isMultiDay: Bool {
        guard let startDate, let endDate else { return false }
        return !Calendar.current.isDate(startDate, inSameDayAs: endDate)
    }
}

/// EventKit objects cross to the fetch queue (EKEventStore reads are thread-safe); the box only
/// carries them across the Sendable boundary.
private struct EKUncheckedBox<T>: @unchecked Sendable { let value: T }
