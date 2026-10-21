// Usage widget (2026-10-20): the pure, Foundation-only part of the self-collected
// Screen Time-like statistics. No AppKit, no SwiftData, no clock: everything takes explicit dates
// and a `Calendar`, so it is unit-tested by the harness (Tests/UsageAccountingTests).
//
//   UsageAccountant   turns the tracker's events (frontmost app changes, idle / active, sleep /
//                     wake, lock / unlock, periodic flushes) into closed time slices per app and
//                     pickups (= unlocks).
//   UsageApportioner  splits a slice at local midnights into per-day seconds.
//   UsageDay          a local calendar day ("2026-10-20"), the storage key of the daily totals.
//   UsageSummary      today's total, top apps, the last 7 days and today's pickups, from the
//                     stored daily rows (what the widget shows).
//   UsageCSV          the CSV export.
import Foundation

// MARK: - Day

/// A calendar day as recorded (local to the calendar in use at the time).
struct UsageDay: Hashable, Comparable, Sendable, CustomStringConvertible {
    var year: Int
    var month: Int
    var day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(_ date: Date, calendar: Calendar) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// Parses "yyyy-MM-dd".
    init?(key: String) {
        let parts = key.split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    /// "yyyy-MM-dd" (the stored key and the CSV date column).
    var key: String { String(format: "%04d-%02d-%02d", year, month, day) }
    var description: String { key }

    /// Local midnight at the start of the day.
    func start(in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    func adding(days: Int, calendar: Calendar) -> UsageDay {
        // noon avoids DST edges when stepping whole days
        let noon = calendar.date(byAdding: .hour, value: 12, to: start(in: calendar)) ?? start(in: calendar)
        return UsageDay(calendar.date(byAdding: .day, value: days, to: noon) ?? noon, calendar: calendar)
    }

    static func < (a: UsageDay, b: UsageDay) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    /// Days older than this are deleted (`retentionDays` = 90 keeps today and the 89 days before).
    static func retentionCutoff(today: UsageDay, retentionDays: Int, calendar: Calendar) -> UsageDay {
        today.adding(days: -(max(retentionDays, 1) - 1), calendar: calendar)
    }
}

// MARK: - Events and slices

/// A closed stretch of time one app was frontmost while the user was present.
struct UsageSlice: Equatable, Sendable {
    var appID: String
    var appName: String
    var start: Date
    var end: Date

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// What the tracker observes. Times are when the thing happened (`idle(since:)` is the time of the
/// last input, which can be well before the idle threshold was noticed).
enum UsageEvent: Equatable, Sendable {
    /// `appID` nil: no frontmost app (or one that is never counted, e.g. loginwindow).
    case activate(appID: String?, name: String, at: Date)
    /// No input since `since` (noticed later, once the idle threshold passed).
    case idle(since: Date)
    /// Input resumed at `at`.
    case active(at: Date)
    case sleep(at: Date)
    case wake(at: Date)
    case lock(at: Date)
    case unlock(at: Date)
    /// Emit the open slice up to `at` and keep counting (periodic persistence). With
    /// `lastInputAt`, only time up to the last input is emitted: the rest stays open, so an idle
    /// cut noticed later (`idle(since:)`) can still take it back.
    case flush(at: Date, lastInputAt: Date? = nil)
    /// Tracking ends (turned off, app quits): close the open slice, forget the frontmost app.
    case stop(at: Date)

    var date: Date {
        switch self {
        case .activate(_, _, let d), .idle(let d), .active(let d), .sleep(let d), .wake(let d),
             .lock(let d), .unlock(let d), .flush(let d, _), .stop(let d):
            return d
        }
    }
}

/// Session accounting: counts the frontmost app's time while the Mac is awake, unlocked and the

struct UsageAccountant: Sendable {
    struct Output: Equatable, Sendable {
        var slices: [UsageSlice] = []
        /// Unlock times (a pickup each; repeated unlock notifications count once).
        var pickups: [Date] = []

        var isEmpty: Bool { slices.isEmpty && pickups.isEmpty }
    }

    /// Apps never counted (bundle identifiers).
    var excludedAppIDs: Set<String>
    /// A gap longer than this between two events is not counted (the tracker sends a flush every
    /// few seconds, so a long gap means the process was suspended or a sleep was missed). nil: off.
    var maximumGap: TimeInterval?

    private(set) var frontmostID: String?
    private(set) var frontmostName: String = ""
    private(set) var isIdle = false
    private(set) var isAsleep = false
    private(set) var isLocked = false
    /// Start of the open slice (non-nil while counting).
    private(set) var segmentStart: Date?
    private var lastEventDate: Date?

    init(excludedAppIDs: Set<String> = [], maximumGap: TimeInterval? = nil, startsLocked: Bool = false) {
        self.excludedAppIDs = excludedAppIDs
        self.maximumGap = maximumGap
        self.isLocked = startsLocked
    }

    var isCounting: Bool { segmentStart != nil }

    private var shouldCount: Bool {
        guard let id = frontmostID, !excludedAppIDs.contains(id) else { return false }
        return !isIdle && !isAsleep && !isLocked
    }

    /// The open slice as of `now` (for live display; nothing is consumed).
    func pendingSlice(at now: Date) -> UsageSlice? {
        guard let start = segmentStart, let id = frontmostID, now > start else { return nil }
        return UsageSlice(appID: id, appName: frontmostName, start: start, end: now)
    }

    mutating func handle(_ event: UsageEvent) -> Output {
        var out = Output()
        let t = event.date

        // `idle(since:)` carries a past date (the last input): it neither moves the gap clock nor
        // counts as the clock going backwards.
        if !event.isIdleEvent {
            // A missed sleep / suspended process: drop the unobserved stretch.
            if let gap = maximumGap, let last = lastEventDate, t.timeIntervalSince(last) > gap, segmentStart != nil {
                close(at: last, into: &out)
                open(at: t)
            }
            // The clock moved backwards: drop the open slice and restart from now.
            if let start = segmentStart, t < start {
                segmentStart = t
            }
            lastEventDate = t
        }

        switch event {
        case .activate(let id, let name, _):
            if id == frontmostID {
                frontmostName = name
            } else {
                close(at: t, into: &out)
                frontmostID = id
                frontmostName = name
            }
        case .idle(let since):
            guard !isIdle else { break }
            // the time since the last input is not use: cut the slice back to it
            close(at: since, into: &out)
            isIdle = true
        case .active:
            isIdle = false
        case .sleep:
            close(at: t, into: &out)
            isAsleep = true
        case .wake:
            isAsleep = false
        case .lock:
            close(at: t, into: &out)
            isLocked = true
        case .unlock:
            if isLocked { out.pickups.append(t) }
            isLocked = false
        case .flush(_, let lastInput):
            if let start = segmentStart {
                let cut = lastInput.map { max(start, min($0, t)) } ?? t
                close(at: cut, into: &out)
                if shouldCount { segmentStart = cut }
            }
        case .stop:
            close(at: t, into: &out)
            frontmostID = nil
            frontmostName = ""
            isIdle = false
        }

        if shouldCount {
            if segmentStart == nil { open(at: t) }
        } else if segmentStart != nil {
            close(at: t, into: &out)
        }
        return out
    }

    private mutating func open(at t: Date) {
        segmentStart = shouldCount ? t : nil
    }

    /// Closes the open slice at `t` (clamped to its start); empty slices are dropped.
    private mutating func close(at t: Date, into out: inout Output) {
        guard let start = segmentStart else { return }
        segmentStart = nil
        guard let id = frontmostID else { return }
        let end = max(t, start)
        if end > start {
            out.slices.append(UsageSlice(appID: id, appName: frontmostName, start: start, end: end))
        }
    }
}

private extension UsageEvent {
    var isIdleEvent: Bool {
        if case .idle = self { return true }
        return false
    }
}

// MARK: - Midnight split

enum UsageApportioner {
    /// The seconds of `slice` per local calendar day (split at midnight; DST days are 23 / 25 h).
    static func split(_ slice: UsageSlice, calendar: Calendar) -> [(day: UsageDay, seconds: TimeInterval)] {
        var result: [(day: UsageDay, seconds: TimeInterval)] = []
        var cursor = slice.start
        while cursor < slice.end {
            let dayStart = calendar.startOfDay(for: cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: dayStart), next > cursor else { break }
            let end = min(next, slice.end)
            result.append((UsageDay(cursor, calendar: calendar), end.timeIntervalSince(cursor)))
            cursor = end
        }
        return result
    }
}

// MARK: - Summary (what the widget shows)

/// One stored daily total.
struct UsageDailyRow: Equatable, Sendable {
    var day: UsageDay
    var appID: String
    var appName: String
    var seconds: TimeInterval
}

struct UsageAppTotal: Equatable, Sendable, Identifiable {
    var appID: String
    var appName: String
    var seconds: TimeInterval
    var id: String { appID }
}

struct UsageSummary: Equatable, Sendable {
    var today: UsageDay
    var todayTotal: TimeInterval
    /// Today's apps, most used first (at most `topCount`).
    var topApps: [UsageAppTotal]
    /// The last 7 days, oldest first, ending today.
    var week: [(day: UsageDay, seconds: TimeInterval)]
    var pickupsToday: Int

    static let empty = UsageSummary(today: UsageDay(year: 1970, month: 1, day: 1), todayTotal: 0, topApps: [], week: [], pickupsToday: 0)

    static func == (a: UsageSummary, b: UsageSummary) -> Bool {
        a.today == b.today && a.todayTotal == b.todayTotal && a.topApps == b.topApps
            && a.pickupsToday == b.pickupsToday
            && a.week.map(\.day) == b.week.map(\.day) && a.week.map(\.seconds) == b.week.map(\.seconds)
    }

    /// Builds the summary from stored rows plus not-yet-stored live seconds. Excluded apps are
    /// left out (excluding an app hides what was recorded before, too).
    static func build(rows: [UsageDailyRow], pickups: [UsageDay: Int], today: UsageDay,
                      excludedAppIDs: Set<String> = [], topCount: Int = 5, calendar: Calendar) -> UsageSummary {
        let visible = rows.filter { !excludedAppIDs.contains($0.appID) && $0.seconds > 0 }
        var todayByApp: [String: UsageAppTotal] = [:]
        var perDay: [UsageDay: TimeInterval] = [:]
        for row in visible {
            perDay[row.day, default: 0] += row.seconds
            guard row.day == today else { continue }
            var total = todayByApp[row.appID] ?? UsageAppTotal(appID: row.appID, appName: row.appName, seconds: 0)
            total.seconds += row.seconds
            if total.appName.isEmpty { total.appName = row.appName }
            todayByApp[row.appID] = total
        }
        let top = todayByApp.values.sorted {
            $0.seconds != $1.seconds ? $0.seconds > $1.seconds
                : $0.appName.localizedStandardCompare($1.appName) == .orderedAscending
        }
        let week = (-6...0).map { offset -> (day: UsageDay, seconds: TimeInterval) in
            let day = today.adding(days: offset, calendar: calendar)
            return (day, perDay[day] ?? 0)
        }
        return UsageSummary(today: today, todayTotal: perDay[today] ?? 0,
                            topApps: Array(top.prefix(max(topCount, 0))), week: week,
                            pickupsToday: pickups[today] ?? 0)
    }
}

// MARK: - CSV

enum UsageCSV {
    static let header = "date,kind,bundle_id,app_name,seconds,count"

    /// One `app` row per day and app (seconds rounded to whole seconds), one `pickups` row per day.
    static func make(rows: [UsageDailyRow], pickups: [UsageDay: Int]) -> String {
        var lines = [header]
        let sorted = rows.sorted { ($0.day, $0.appID) < ($1.day, $1.appID) }
        var days = Set(rows.map(\.day))
        days.formUnion(pickups.keys)
        var byDay: [UsageDay: [UsageDailyRow]] = [:]
        for row in sorted { byDay[row.day, default: []].append(row) }
        for day in days.sorted() {
            for row in byDay[day] ?? [] {
                lines.append([day.key, "app", field(row.appID), field(row.appName),
                              String(Int(row.seconds.rounded())), ""].joined(separator: ","))
            }
            if let count = pickups[day], count > 0 {
                lines.append([day.key, "pickups", "", "", "", String(count)].joined(separator: ","))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// RFC 4180 quoting when needed.
    static func field(_ s: String) -> String {
        guard s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

// MARK: - Formatting

enum UsageFormatting {
    /// "3h 12m", "45m", "<1m" (0 → "0m").
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded(.down))
        if seconds > 0 && minutes == 0 { return "<1m" }
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}
