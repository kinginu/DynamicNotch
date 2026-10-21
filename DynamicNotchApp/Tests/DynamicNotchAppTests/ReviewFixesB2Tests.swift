// Review fixes (2026-10-21): live-activity selection, tray rename, calendar selection, Downloads
// polling / Clear Old. Files are created only in a fresh temporary folder.
import Foundation
import Testing
@testable import DynamicNotchApp

@Suite("Live activity selection") struct LiveActivitySelectionRuleTests {
    private let ordered = LiveActivity.byPriority

    @Test func batteryWinsOnBatteryOverOrdinaryActivities() {
        #expect(LiveActivitySelectionManager.select(from: [.battery, .timerExpired, .media], ordered: ordered, onBattery: true) == .battery)
        #expect(LiveActivitySelectionManager.select(from: [.battery, .timerExpired], ordered: ordered, onBattery: false) == .timerExpired)
    }

    @Test func hudAndSafetyAlertsOutrankTheBatteryRule() {
        #expect(LiveActivitySelectionManager.select(from: [.battery, .hud], ordered: ordered, onBattery: true) == .hud)
        // every `.always`-gated activity (the FanControl alert in the app) beats the battery rule
        for activity in LiveActivity.allCases {
            if case .always = activity.descriptor.gate {
                #expect(activity.outranksBatteryRule)
                #expect(LiveActivitySelectionManager.select(from: [.battery, activity], ordered: ordered, onBattery: true) == activity)
            }
        }
        #expect(!LiveActivity.battery.outranksBatteryRule)
        #expect(!LiveActivity.timerExpired.outranksBatteryRule)
    }

    #if canImport(FanControlKit)
    @Test func fanAlertBeatsLowBattery() {
        #expect(LiveActivitySelectionManager.select(from: [.battery, .fanAlert], ordered: ordered, onBattery: true) == .fanAlert)
    }
    #endif
}

@Suite("Tray rename") struct TrayRenameTests {
    private let file = URL(fileURLWithPath: "/tmp/tray/ABC/report.pdf")

    @Test func keepsTheWholeTypedName() {
        #expect(TrayFile.renamedURL(for: file, typed: "report.v2.pdf")?.lastPathComponent == "report.v2.pdf")
        #expect(TrayFile.renamedURL(for: file, typed: "notes.txt")?.lastPathComponent == "notes.txt")
    }

    @Test func addsTheExtensionWhenNoneIsTyped() {
        #expect(TrayFile.renamedURL(for: file, typed: "summary")?.lastPathComponent == "summary.pdf")
        #expect(TrayFile.renamedURL(for: URL(fileURLWithPath: "/tmp/tray/ABC/README"), typed: "INFO")?.lastPathComponent == "INFO")
    }

    @Test func staysInTheSameFolder() {
        #expect(TrayFile.renamedURL(for: file, typed: "x.pdf")?.deletingLastPathComponent().path == "/tmp/tray/ABC")
    }

    @Test func ignoresUnchangedEmptyAndInvalidNames() {
        #expect(TrayFile.renamedURL(for: file, typed: "report.pdf") == nil)
        #expect(TrayFile.renamedURL(for: file, typed: "report") == nil)      // + .pdf = unchanged
        #expect(TrayFile.renamedURL(for: file, typed: "   ") == nil)
        #expect(TrayFile.renamedURL(for: file, typed: "a/b.pdf") == nil)
        #expect(TrayFile.renamedURL(for: file, typed: "..") == nil)
    }
}

@Suite("Calendar selection") struct CalendarSavedSelectionTests {
    @Test func nilMeansAllExplicitEmptyMeansNone() {
        var s = CalendarSelectionSettings()
        #expect(CalendarManager.savedSelection(s) == .all)
        s.savedIdentifiers = []
        #expect(CalendarManager.savedSelection(s) == .all)        // legacy empty list
        s.selectionWasExplicit = true
        #expect(CalendarManager.savedSelection(s) == .none)
        s.savedIdentifiers = ["a", "b"]
        #expect(CalendarManager.savedSelection(s) == .some(["a", "b"]))
    }
}

@Suite("Downloads watcher") struct DownloadsWatcherReviewTests {
    private func scratchFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dn-downloads-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Finding: every 1 s poll re-summed every listed folder.
    @Test func folderSizesAreReusedWhileUnchanged() throws {
        let root = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let sub = root.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data(count: 1000).write(to: sub.appendingPathComponent("a.bin"))
        try Data(count: 10).write(to: root.appendingPathComponent("file.txt"))

        var measured = 0
        let measure: (URL) -> Int64? = { url in measured += 1; return DownloadsWatcher.directorySize(url) }
        let first = DownloadsWatcher.read(folder: root, showHidden: false, limit: 10, now: Date(), measure: measure)
        #expect(measured == 1)
        #expect(first.items.first { $0.name == "Project" }?.size == 1000)
        let second = DownloadsWatcher.read(folder: root, showHidden: false, limit: 10, now: Date(),
                                           knownSizes: first.directorySizes, measure: measure)
        #expect(measured == 1)
        #expect(second.items.first { $0.name == "Project" }?.size == 1000)
        #expect(second.directorySizes == first.directorySizes)
        // a changed folder (new modification date) is measured again
        var stale = first.directorySizes
        for key in stale.keys { stale[key]?.modified = .distantPast }
        _ = DownloadsWatcher.read(folder: root, showHidden: false, limit: 10, now: Date(), knownSizes: stale, measure: measure)
        #expect(measured == 2)
    }

    @Test func pollingStopsWhenNothingIsActive() {
        #expect(DownloadsWatcher.pollInterval(hasActiveDownloads: true, listsPartial: false) == 1)
        #expect(DownloadsWatcher.pollInterval(hasActiveDownloads: false, listsPartial: true) == 15)
        #expect(DownloadsWatcher.pollInterval(hasActiveDownloads: false, listsPartial: false) == nil)
    }

    /// Finding: a confirmed Clear Old plan recycled its URLs as listed, even if a file had been
    /// replaced by a new download with the same name since.
    @Test func confirmedPlanIsRecheckedAgainstTheFolder() throws {
        let root = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("old.zip")
        let replaced = root.appendingPathComponent("replaced.dmg")
        try Data(count: 5).write(to: old)
        try Data(count: 5).write(to: replaced)
        // a plan computed "in 30 days" picks both; "now" a fresh look picks neither
        let later = Date().addingTimeInterval(30 * 86_400)
        let plan = DownloadsWatcher.oldItems(in: root, days: 7, now: later)
        #expect(Set(plan.urls.map(\.lastPathComponent)) == ["old.zip", "replaced.dmg"])
        let fresh = DownloadsWatcher.oldItems(in: root, days: 7, now: Date(), measure: false)
        #expect(DownloadsWatcher.revalidated(plan, against: fresh).urls.isEmpty)
        let still = DownloadsWatcher.ClearPlan(urls: [old], bytes: 0, days: 7)
        #expect(DownloadsWatcher.revalidated(plan, against: still).urls.map(\.lastPathComponent) == ["old.zip"])
        // nothing was moved: only the plans were computed
        #expect(FileManager.default.fileExists(atPath: old.path))
    }
}
