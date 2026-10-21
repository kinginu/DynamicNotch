// RemindersManager — Apple Reminders integration of the Reminders widget (2026-10-20).
//
// User decision: to-dos must not be siloed in this app. The in-app SwiftData to-do list
// (TodoItem / TodoWidgetView / TodoListWidgetSettings) was discarded without migration; the Nook
// now shows, adds and completes reminders of the user's Reminders lists through EventKit.
//
// Flow:
//   - Access: `EKEventStore.authorizationStatus(for: .reminder)`. Nothing is requested at launch;
//     the widget / settings show "Allow Access", which calls `requestFullAccessToReminders()`
//     (system prompt, once). Denied / restricted / write-only → "Open System Settings"
//     (Privacy & Security ▸ Reminders). The status is re-read every time the widget appears.
//   - Lists: `RemindersWidgetSettings.listIdentifiers` (empty = the default list for new
//     reminders). New reminders go to `newReminderListIdentifier` if it is one of the shown lists,
//     else to the first shown list.
//   - Fetch: incomplete reminders of the shown lists (`predicateForIncompleteReminders`), mapped to
//     value rows on EventKit's queue, sorted by due date (undated last), then creation date.
//   - Changes: `.EKEventStoreChanged` (edits in Reminders, iCloud sync) → reload, coalesced 250 ms.
//   - Completing: the row's circle fills, and after a short delay (tap again to undo, as in
//     Reminders) `isCompleted = true` is saved through the store.
// Works offline: EventKit reads and writes the local store; iCloud syncs it later.
import AppKit
import EventKit
import Foundation
import Observation
import SwiftUI
import os

private let logger = Logger(subsystem: "com.example.dynamicnotch.DynamicNotch", category: "reminders")

/// One incomplete reminder, as shown by the widget (value copy of an `EKReminder`).
struct ReminderRow: Identifiable, Hashable, Sendable {
    /// `calendarItemIdentifier`.
    let id: String
    let title: String
    /// Due date (start of day for date-only reminders).
    let dueDate: Date?
    /// The due date has a time of day.
    let dueHasTime: Bool
    let creationDate: Date?
    let listIdentifier: String
    let listColor: CodableColorComponents

    func isOverdue(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let dueDate else { return false }
        return dueHasTime ? dueDate < now : dueDate < calendar.startOfDay(for: now)
    }
}

/// A Reminders list (`EKCalendar` with entity type `.reminder`).
struct ReminderList: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let sourceTitle: String
    let color: CodableColorComponents
}

/// Sendable RGBA copy of an `EKCalendar.cgColor`.
struct CodableColorComponents: Hashable, Sendable {
    var red: Double, green: Double, blue: Double, alpha: Double

    init(_ cgColor: CGColor?) {
        let color = cgColor.flatMap { NSColor(cgColor: $0)?.usingColorSpace(.sRGB) } ?? .systemBlue
        red = color.redComponent; green = color.greenComponent; blue = color.blueComponent; alpha = color.alphaComponent
    }

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
}

@MainActor
@Observable
final class RemindersManager {
    static let shared = RemindersManager()

    @ObservationIgnored let store = EKEventStore()

    private(set) var authorizationStatus: EKAuthorizationStatus = .notDetermined
    /// Incomplete reminders of the shown lists, sorted.
    private(set) var reminders: [ReminderRow] = []
    /// All Reminders lists (for settings), sorted by account, then title.
    private(set) var lists: [ReminderList] = []
    /// Lists currently shown (resolved from the settings; the default list when none is chosen).
    private(set) var shownLists: [ReminderList] = []
    /// Reminders whose circle was ticked and that are about to be saved as completed.
    private(set) var completingIDs: Set<String> = []
    /// True until the first fetch after access was granted has finished.
    private(set) var isLoading = false
    /// Last save error (shown as a caption), cleared on the next successful save.
    private(set) var lastError: String?

    @ObservationIgnored private var changeObserver: NSObjectProtocol?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var completionTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var generation = 0

    /// Delay between ticking a reminder and saving it (the row stays, filled, so a second tap undoes).
    static let completionDelay: Duration = .milliseconds(900)

    private init() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleReload() }
        }
        #if DEBUG
        loadDebugSampleIfRequested()
        #endif
    }

    // MARK: - Access

    var hasAccess: Bool { authorizationStatus == .fullAccess }

    func refreshAuthorizationStatus() {
        #if DEBUG
        if debugSample { return }
        #endif
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if status != authorizationStatus { authorizationStatus = status }
        if !hasAccess { reminders = []; lists = []; shownLists = [] }
    }

    /// Shows the system prompt (only while the status is `.notDetermined`).
    func requestAccess() async {
        do {
            _ = try await store.requestFullAccessToReminders()
        } catch {
            logger.error("access request failed: \(String(describing: error), privacy: .public)")
        }
        refreshAuthorizationStatus()
        if hasAccess { reload() }
    }

    /// System Settings ▸ Privacy & Security ▸ Reminders.
    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Fetching

    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }

    func reload() {
        #if DEBUG
        if debugSample { return }
        #endif
        refreshAuthorizationStatus()
        guard hasAccess else { return }

        let calendars = store.calendars(for: .reminder)
        lists = calendars.map(Self.list(for:))
            .sorted { ($0.sourceTitle, $0.title) < ($1.sourceTitle, $1.title) }
        let shownCalendars = resolveShownCalendars(all: calendars)
        shownLists = shownCalendars.map(Self.list(for:))
        guard !shownCalendars.isEmpty else {
            reminders = []
            return
        }

        generation += 1
        let token = generation
        if reminders.isEmpty { isLoading = true }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil,
                                                              calendars: shownCalendars)
        store.fetchReminders(matching: predicate) { [weak self] fetched in
            // EventKit's queue: copy into value rows before hopping to the main actor.
            let calendar = Calendar.current
            let rows = (fetched ?? []).map { reminder -> ReminderRow in
                let components = reminder.dueDateComponents
                var due: Date?
                var hasTime = false
                if let components {
                    hasTime = components.hour != nil
                    var c = components
                    if c.calendar == nil { c.calendar = calendar }
                    due = c.date ?? calendar.date(from: components)
                }
                return ReminderRow(
                    id: reminder.calendarItemIdentifier,
                    title: reminder.title ?? "",
                    dueDate: due,
                    dueHasTime: hasTime,
                    creationDate: reminder.creationDate,
                    listIdentifier: reminder.calendar?.calendarIdentifier ?? "",
                    listColor: CodableColorComponents(reminder.calendar?.cgColor)
                )
            }
            let sorted = Self.sorted(rows)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let manager = self, manager.generation == token else { return }
                    manager.isLoading = false
                    if manager.reminders != sorted {
                        withAnimation(.easeInOut(duration: 0.2)) { manager.reminders = sorted }
                    }
                }
            }
        }
    }

    /// Due date ascending (undated last), then creation date ascending, then title.
    nonisolated static func sorted(_ rows: [ReminderRow]) -> [ReminderRow] {
        rows.sorted { a, b in
            switch (a.dueDate, b.dueDate) {
            case let (x?, y?) where x != y: return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: break
            }
            let ca = a.creationDate ?? .distantFuture, cb = b.creationDate ?? .distantFuture
            if ca != cb { return ca < cb }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    private static func list(for calendar: EKCalendar) -> ReminderList {
        ReminderList(id: calendar.calendarIdentifier, title: calendar.title,
                     sourceTitle: calendar.source?.title ?? "", color: CodableColorComponents(calendar.cgColor))
    }

    /// Lists chosen in the settings that still exist; the default list when none is chosen (or
    /// all chosen lists were deleted).
    private func resolveShownCalendars(all: [EKCalendar]) -> [EKCalendar] {
        let ids = SettingsStore[.remindersWidgetSettings].listIdentifiers
        let chosen = all.filter { ids.contains($0.calendarIdentifier) }
            .sorted { (ids.firstIndex(of: $0.calendarIdentifier) ?? 0) < (ids.firstIndex(of: $1.calendarIdentifier) ?? 0) }
        if !chosen.isEmpty { return chosen }
        if let fallback = store.defaultCalendarForNewReminders() { return [fallback] }
        return all.first.map { [$0] } ?? []
    }

    /// The list new reminders are added to.
    var targetList: ReminderList? {
        let wanted = SettingsStore[.remindersWidgetSettings].newReminderListIdentifier
        return shownLists.first { $0.id == wanted } ?? shownLists.first
    }

    // MARK: - Editing

    /// Creates a reminder (no due date) in `targetList`.
    func add(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        #if DEBUG
        if debugSample {
            reminders.append(ReminderRow(id: UUID().uuidString, title: trimmed, dueDate: nil, dueHasTime: false,
                                         creationDate: Date(), listIdentifier: shownLists.first?.id ?? "",
                                         listColor: shownLists.first?.color ?? .init(nil)))
            return
        }
        #endif
        guard hasAccess, let target = targetList,
              let calendar = store.calendar(withIdentifier: target.id) else { return }
        let reminder = EKReminder(eventStore: store)
        reminder.title = trimmed
        reminder.calendar = calendar
        do {
            try store.save(reminder, commit: true)
            lastError = nil
        } catch {
            report(error)
        }
        reload()
    }

    /// Ticks (or, during the delay, unticks) a reminder. Saved as completed after `completionDelay`.
    func toggleCompletion(_ id: String) {
        if completingIDs.contains(id) {
            completionTasks.removeValue(forKey: id)?.cancel()
            completingIDs.remove(id)
            return
        }
        completingIDs.insert(id)
        completionTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: Self.completionDelay)
            guard !Task.isCancelled else { return }
            self?.complete(id)
        }
    }

    private func complete(_ id: String) {
        completionTasks[id] = nil
        defer { completingIDs.remove(id) }
        #if DEBUG
        if debugSample {
            withAnimation(.easeInOut(duration: 0.2)) { reminders.removeAll { $0.id == id } }
            return
        }
        #endif
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            reload()
            return
        }
        reminder.isCompleted = true // also sets completionDate
        do {
            try store.save(reminder, commit: true)
            lastError = nil
            withAnimation(.easeInOut(duration: 0.2)) { reminders.removeAll { $0.id == id } }
        } catch {
            report(error)
            reload()
        }
    }

    private func report(_ error: any Error) {
        logger.error("save failed: \(String(describing: error), privacy: .public)")
        lastError = error.localizedDescription
    }

    // MARK: - DEBUG sample data

    #if DEBUG
    /// DN_DEBUG_REMINDERS_SAMPLE=1 (development instances, snapshots): fixed sample rows instead of
    /// EventKit, without asking for access. Nothing is read from or written to Reminders.
    @ObservationIgnored private var debugSample = false

    private func loadDebugSampleIfRequested() {
        guard ProcessInfo.processInfo.environment["DN_DEBUG_REMINDERS_SAMPLE"] == "1" else { return }
        debugSample = true
        authorizationStatus = .fullAccess
        let orange = CodableColorComponents(red: 1, green: 0.58, blue: 0)
        let list = ReminderList(id: "sample", title: String(localized: "Reminders"), sourceTitle: "iCloud", color: orange)
        lists = [list]; shownLists = [list]
        let cal = Calendar.current, now = Date(), today = cal.startOfDay(for: now)
        func row(_ title: String, _ due: Date?, time: Bool, created: Int) -> ReminderRow {
            ReminderRow(id: title, title: title, dueDate: due, dueHasTime: time,
                        creationDate: now.addingTimeInterval(TimeInterval(created) * 60),
                        listIdentifier: "sample", listColor: orange)
        }
        reminders = Self.sorted([
            row("Pay the electricity bill", cal.date(byAdding: .day, value: -1, to: today), time: false, created: 0),
            row("Call the dentist", now.addingTimeInterval(2 * 3600), time: true, created: 1),
            row("Pick up dry cleaning", cal.date(byAdding: .day, value: 1, to: today), time: false, created: 2),
            row("Buy oat milk", nil, time: false, created: 3),
            row("Book train tickets for the weekend trip to Kyoto", nil, time: false, created: 4),
        ])
    }
    #endif
}
