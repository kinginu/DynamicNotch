// Usage widget (2026-10-20): SwiftData storage of the daily totals.
//
// Own container (not NookModelContainer's Note schema, so a schema change here never touches the
// notes store): `~/Library/Application Support/<bundle id>/Usage.store`. Two models:
//   UsageAppDayRecord   seconds one app was frontmost and in use on a local day ("yyyy-MM-dd")
//   UsageDayRecord      pickups (unlocks) on a local day
// Retention: days before `UsageDay.retentionCutoff(…, 90)` are deleted at launch, at midnight and
// when tracking is turned on. The whole store is small (≤ 90 days × the apps used), so it is
// loaded once and kept in memory; writes go to the model objects and are saved in batches by the
// tracker (every 30 s and when tracking stops).
//
// DN_CLT_HARNESS: type-check-only PersistentModel conformances (no SwiftDataMacros in the
// Command Line Tools), as in Note.swift. Only the Xcode target's `@Model` classes run.
import Foundation
import Observation
import SwiftData

#if DN_CLT_HARNESS
@Observable
final class UsageAppDayRecord {
    var dayKey: String = ""
    var appID: String = ""
    var appName: String = ""
    var seconds: Double = 0

    @ObservationIgnored var persistentBackingData: any BackingData<UsageAppDayRecord>

    init(dayKey: String, appID: String, appName: String, seconds: Double) {
        self.persistentBackingData = UsageAppDayRecord.createBackingData()
        self.dayKey = dayKey
        self.appID = appID
        self.appName = appName
        self.seconds = seconds
    }

    required init(backingData: any BackingData<UsageAppDayRecord>) {
        self.persistentBackingData = backingData
    }

    static var schemaMetadata: [Schema.PropertyMetadata] { [] }
}
extension UsageAppDayRecord: PersistentModel {}

@Observable
final class UsageDayRecord {
    var dayKey: String = ""
    var pickups: Int = 0

    @ObservationIgnored var persistentBackingData: any BackingData<UsageDayRecord>

    init(dayKey: String, pickups: Int) {
        self.persistentBackingData = UsageDayRecord.createBackingData()
        self.dayKey = dayKey
        self.pickups = pickups
    }

    required init(backingData: any BackingData<UsageDayRecord>) {
        self.persistentBackingData = backingData
    }

    static var schemaMetadata: [Schema.PropertyMetadata] { [] }
}
extension UsageDayRecord: PersistentModel {}
#else
@Model
final class UsageAppDayRecord {
    var dayKey: String = ""
    var appID: String = ""
    var appName: String = ""
    var seconds: Double = 0

    init(dayKey: String, appID: String, appName: String, seconds: Double) {
        self.dayKey = dayKey
        self.appID = appID
        self.appName = appName
        self.seconds = seconds
    }
}

@Model
final class UsageDayRecord {
    var dayKey: String = ""
    var pickups: Int = 0

    init(dayKey: String, pickups: Int) {
        self.dayKey = dayKey
        self.pickups = pickups
    }
}
#endif

/// The daily totals (SwiftData), cached in memory. Main actor only.
@MainActor
final class UsageStore {
    static let shared = UsageStore()

    private var container: ModelContainer?
    private var loaded = false
    private var apps: [String: UsageAppDayRecord] = [:]    // "dayKey|appID"
    private var days: [String: UsageDayRecord] = [:]       // dayKey
    private var dirty = false

    static var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.example.dynamicnotch.DynamicNotch", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("Usage.store")
    }

    private var context: ModelContext? {
        loadIfNeeded()
        return container?.mainContext
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        let schema = Schema([UsageAppDayRecord.self, UsageDayRecord.self])
        do {
            container = try ModelContainer(for: schema, configurations: ModelConfiguration("Usage", schema: schema, url: Self.storeURL))
        } catch {
            NSLog("[Usage] ModelContainer (on disk) failed: %@", String(describing: error))
            container = try? ModelContainer(for: schema, configurations: ModelConfiguration("Usage", schema: schema, isStoredInMemoryOnly: true))
        }
        guard let context = container?.mainContext else { return }
        context.autosaveEnabled = false
        for record in (try? context.fetch(FetchDescriptor<UsageAppDayRecord>())) ?? [] {
            let key = record.dayKey + "|" + record.appID
            if let existing = apps[key] {
                // merge duplicates (should not happen; keeps the store consistent if it does)
                existing.seconds += record.seconds
                context.delete(record)
                dirty = true
            } else {
                apps[key] = record
            }
        }
        for record in (try? context.fetch(FetchDescriptor<UsageDayRecord>())) ?? [] {
            if let existing = days[record.dayKey] {
                existing.pickups += record.pickups
                context.delete(record)
                dirty = true
            } else {
                days[record.dayKey] = record
            }
        }
    }

    // MARK: Writing

    func add(seconds: TimeInterval, appID: String, appName: String, day: UsageDay) {
        guard seconds > 0, let context else { return }
        let key = day.key + "|" + appID
        if let record = apps[key] {
            record.seconds += seconds
            if !appName.isEmpty, record.appName != appName { record.appName = appName }
        } else {
            let record = UsageAppDayRecord(dayKey: day.key, appID: appID, appName: appName, seconds: seconds)
            context.insert(record)
            apps[key] = record
        }
        dirty = true
    }

    func addPickup(day: UsageDay) {
        guard let context else { return }
        if let record = days[day.key] {
            record.pickups += 1
        } else {
            let record = UsageDayRecord(dayKey: day.key, pickups: 1)
            context.insert(record)
            days[day.key] = record
        }
        dirty = true
    }

    /// Deletes the days before the retention cutoff.
    func prune(today: UsageDay, calendar: Calendar = .current) {
        guard let context else { return }
        let cutoff = UsageDay.retentionCutoff(today: today, retentionDays: UsageWidgetSettings.retentionDays, calendar: calendar)
        for (key, record) in apps where (UsageDay(key: record.dayKey) ?? cutoff) < cutoff {
            context.delete(record)
            apps[key] = nil
            dirty = true
        }
        for (key, record) in days where (UsageDay(key: record.dayKey) ?? cutoff) < cutoff {
            context.delete(record)
            days[key] = nil
            dirty = true
        }
    }

    /// Deletes everything.
    func clearAll() {
        guard let context else { return }
        for record in apps.values { context.delete(record) }
        for record in days.values { context.delete(record) }
        apps = [:]
        days = [:]
        dirty = true
        save()
    }

    func save() {
        guard dirty, let context = container?.mainContext else { return }
        do {
            try context.save()
            dirty = false
        } catch {
            NSLog("[Usage] save failed: %@", String(describing: error))
        }
    }

    // MARK: Reading

    var rows: [UsageDailyRow] {
        loadIfNeeded()
        return apps.values.compactMap { record in
            guard let day = UsageDay(key: record.dayKey) else { return nil }
            return UsageDailyRow(day: day, appID: record.appID, appName: record.appName, seconds: record.seconds)
        }
    }

    var pickups: [UsageDay: Int] {
        loadIfNeeded()
        var result: [UsageDay: Int] = [:]
        for record in days.values {
            if let day = UsageDay(key: record.dayKey) { result[day, default: 0] += record.pickups }
        }
        return result
    }

    /// Number of days with any record, and the earliest one.
    var recordedDays: (count: Int, first: UsageDay?) {
        var all = Set(rows.map(\.day))
        all.formUnion(pickups.keys)
        return (all.count, all.min())
    }
}
