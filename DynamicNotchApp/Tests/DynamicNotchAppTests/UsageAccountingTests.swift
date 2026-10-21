// Session accounting of the Usage widget (Sources/UsageAccounting.swift): idle splits, midnight
// rollover, sleep / lock, pickups, exclusions, summaries and the CSV export. Pure types only
// (fixed dates and calendars; no tracker, no SwiftData).
//   swift test --filter UsageAccounting
import Foundation
import Testing
@testable import DynamicNotchApp

private func calendar(_ tz: String) -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: tz)!
    return c
}

private let tokyo = calendar("Asia/Tokyo")
private let newYork = calendar("America/New_York")

/// 2026-10-20 hh:mm:ss in `cal`.
private func at(_ h: Int, _ m: Int = 0, _ s: Int = 0, day: Int = 20, month: Int = 10, cal: Calendar = tokyo) -> Date {
    cal.date(from: DateComponents(year: 2026, month: month, day: day, hour: h, minute: m, second: s))!
}

/// Feeds events and collects every output.
private func run(_ events: [UsageEvent], accountant: inout UsageAccountant) -> UsageAccountant.Output {
    var all = UsageAccountant.Output()
    for e in events {
        let out = accountant.handle(e)
        all.slices += out.slices
        all.pickups += out.pickups
    }
    return all
}

private func run(_ events: [UsageEvent], excluded: Set<String> = [], maximumGap: TimeInterval? = nil) -> UsageAccountant.Output {
    var a = UsageAccountant(excludedAppIDs: excluded, maximumGap: maximumGap)
    return run(events, accountant: &a)
}

private func seconds(_ out: UsageAccountant.Output, _ app: String) -> TimeInterval {
    out.slices.filter { $0.appID == app }.map(\.duration).reduce(0, +)
}

@Suite("UsageAccountant")
struct UsageAccountantTests {
    @Test func switchingAppsClosesTheSliceAtTheSwitch() {
        let out = run([
            .activate(appID: "a", name: "A", at: at(9)),
            .activate(appID: "b", name: "B", at: at(9, 10)),
            .stop(at: at(9, 15)),
        ])
        #expect(out.slices.count == 2)
        #expect(seconds(out, "a") == 600)
        #expect(seconds(out, "b") == 300)
        #expect(out.slices[0].appName == "A")
    }

    @Test func idleCutsTheSliceBackToTheLastInput() {
        // threshold noticed at 9:20, but the last input was at 9:15
        let out = run([
            .activate(appID: "a", name: "A", at: at(9)),
            .flush(at: at(9, 20), lastInputAt: at(9, 15)),  // a flush before idle is noticed
            .idle(since: at(9, 15)),
            .active(at: at(9, 40)),
            .stop(at: at(9, 50)),
        ])
        // the flush emitted only up to the last input, so 9:15–9:20 is not counted
        #expect(seconds(out, "a") == 15 * 60 + 10 * 60)
        #expect(out.slices.map(\.end).contains(at(9, 15)))
    }

    @Test func flushWithoutLastInputEmitsUpToNow() {
        // without `lastInputAt` a flushed stretch is final: a later idle cut cannot take it back
        let out = run([
            .activate(appID: "a", name: "A", at: at(9)),
            .flush(at: at(9, 20)),
            .idle(since: at(9, 15)),
            .stop(at: at(9, 30)),
        ])
        #expect(seconds(out, "a") == 20 * 60)
    }

    @Test func flushKeepsTimeAfterTheLastInputOpen() {
        var a = UsageAccountant()
        _ = a.handle(.activate(appID: "a", name: "A", at: at(9)))
        let out = a.handle(.flush(at: at(9, 2), lastInputAt: at(9, 1, 30)))
        #expect(out.slices.map(\.duration) == [90])
        #expect(a.segmentStart == at(9, 1, 30))
        // input resumed: the next flush includes the stretch after the earlier last input
        let next = a.handle(.flush(at: at(9, 3), lastInputAt: at(9, 3)))
        #expect(next.slices.map(\.duration) == [90])
    }

    @Test func idleBeforeAnyFlushCountsOnlyUntilTheLastInput() {
        let out = run([
            .activate(appID: "a", name: "A", at: at(9)),
            .idle(since: at(9, 15)),
            .active(at: at(9, 40)),
            .stop(at: at(9, 50)),
        ])
        #expect(out.slices.map(\.duration) == [900, 600])
        #expect(out.slices[1].start == at(9, 40))
    }

    @Test func repeatedIdleIsIgnored() {
        let out = run([
            .activate(appID: "a", name: "A", at: at(9)),
            .idle(since: at(9, 5)),
            .idle(since: at(9, 7)),
            .active(at: at(9, 30)),
            .stop(at: at(9, 31)),
        ])
        #expect(seconds(out, "a") == 5 * 60 + 60)
    }

    @Test func appSwitchWhileIdleIsNotCountedUntilInput() {
        let out = run([
            .activate(appID: "a", name: "A", at: at(9)),
            .idle(since: at(9, 1)),
            .activate(appID: "b", name: "B", at: at(9, 2)),   // e.g. an app activating itself
            .active(at: at(9, 10)),
            .stop(at: at(9, 12)),
        ])
        #expect(seconds(out, "a") == 60)
        #expect(seconds(out, "b") == 120)
    }

    @Test func sleepPausesAndWakeResumes() {
        let out = run([
            .activate(appID: "a", name: "A", at: at(22)),
            .sleep(at: at(22, 30)),
            .wake(at: at(23, 30)),
            .stop(at: at(23, 45)),
        ])
        #expect(out.slices.map(\.duration) == [1800, 900])
    }

    @Test func lockedWakeDoesNotCountUntilUnlock() {
        let out = run([
            .activate(appID: "a", name: "A", at: at(8)),
            .lock(at: at(8, 10)),
            .sleep(at: at(8, 11)),
            .wake(at: at(9)),
            .unlock(at: at(9, 2)),
            .stop(at: at(9, 3)),
        ])
        #expect(out.slices.map(\.duration) == [600, 60])
        #expect(out.pickups == [at(9, 2)])
    }

    @Test func duplicateUnlockCountsOnePickup() {
        let out = run([
            .lock(at: at(8)),
            .unlock(at: at(8, 1)),
            .unlock(at: at(8, 1, 1)),
            .lock(at: at(12)),
            .unlock(at: at(13)),
        ])
        #expect(out.pickups.count == 2)
        #expect(out.slices.isEmpty)  // no frontmost app yet
    }

    @Test func startsLockedCountsTheFirstUnlock() {
        var a = UsageAccountant(startsLocked: true)
        let out = run([
            .activate(appID: "a", name: "A", at: at(7)),
            .unlock(at: at(7, 5)),
            .stop(at: at(7, 10)),
        ], accountant: &a)
        #expect(out.pickups == [at(7, 5)])
        #expect(out.slices.map(\.duration) == [300])
    }

    @Test func flushEmitsProgressAndKeepsCounting() {
        var a = UsageAccountant()
        _ = a.handle(.activate(appID: "a", name: "A", at: at(9)))
        let first = a.handle(.flush(at: at(9, 1)))
        #expect(first.slices.map(\.duration) == [60])
        #expect(a.isCounting)
        #expect(a.pendingSlice(at: at(9, 2))?.duration == 60)
        let second = a.handle(.flush(at: at(9, 3)))
        #expect(second.slices.first?.start == at(9, 1))
    }

    @Test func excludedAppsAreNotCounted() {
        let out = run([
            .activate(appID: "a", name: "A", at: at(9)),
            .activate(appID: "secret", name: "Secret", at: at(9, 5)),
            .activate(appID: "a", name: "A", at: at(9, 20)),
            .stop(at: at(9, 25)),
        ], excluded: ["secret"])
        #expect(seconds(out, "secret") == 0)
        #expect(seconds(out, "a") == 10 * 60)
    }

    @Test func excludingTheCurrentAppTakesEffectAtTheNextEvent() {
        var a = UsageAccountant()
        _ = a.handle(.activate(appID: "a", name: "A", at: at(9)))
        a.excludedAppIDs = ["a"]
        let out = a.handle(.flush(at: at(9, 10)))
        #expect(out.slices.map(\.duration) == [600])  // time before the change still counts
        #expect(!a.isCounting)
        #expect(a.handle(.flush(at: at(9, 20))).slices.isEmpty)
    }

    @Test func reactivatingTheSameAppDoesNotSplit() {
        let out = run([
            .activate(appID: "a", name: "A", at: at(9)),
            .activate(appID: "a", name: "A renamed", at: at(9, 5)),
            .stop(at: at(9, 10)),
        ])
        #expect(out.slices.count == 1)
        #expect(out.slices[0].duration == 600)
        #expect(out.slices[0].appName == "A renamed")
    }

    @Test func noFrontmostAppCountsNothing() {
        let out = run([
            .activate(appID: "a", name: "A", at: at(9)),
            .activate(appID: nil, name: "", at: at(9, 1)),
            .flush(at: at(9, 30)),
            .stop(at: at(9, 40)),
        ])
        #expect(seconds(out, "a") == 60)
        #expect(out.slices.count == 1)
    }

    @Test func longGapBetweenEventsIsDropped() {
        // a missed sleep: the next event comes 2 h later
        let out = run([
            .activate(appID: "a", name: "A", at: at(9)),
            .flush(at: at(9, 1)),
            .flush(at: at(11, 1)),
            .flush(at: at(11, 2)),
        ], maximumGap: 600)
        #expect(seconds(out, "a") == 120)
    }

    @Test func clockGoingBackwardsDoesNotProduceNegativeTime() {
        let out = run([
            .activate(appID: "a", name: "A", at: at(9)),
            .flush(at: at(8)),      // clock set back an hour
            .flush(at: at(8, 5)),
        ])
        #expect(out.slices.allSatisfy { $0.duration > 0 })
        #expect(seconds(out, "a") == 300)
    }

    @Test func stopForgetsTheFrontmostApp() {
        var a = UsageAccountant()
        _ = run([.activate(appID: "a", name: "A", at: at(9)), .stop(at: at(9, 1))], accountant: &a)
        #expect(a.frontmostID == nil)
        #expect(a.handle(.flush(at: at(10))).slices.isEmpty)
    }
}

@Suite("UsageApportioner and UsageDay")
struct UsageApportionerTests {
    @Test func midnightRolloverSplitsAcrossDays() {
        let slice = UsageSlice(appID: "a", appName: "A", start: at(23, 30), end: at(0, 45, day: 21))
        let parts = UsageApportioner.split(slice, calendar: tokyo)
        #expect(parts.map(\.day) == [UsageDay(year: 2026, month: 10, day: 20), UsageDay(year: 2026, month: 10, day: 21)])
        #expect(parts.map(\.seconds) == [1800, 2700])
    }

    @Test func multiDaySliceSplitsIntoWholeDays() {
        let slice = UsageSlice(appID: "a", appName: "A", start: at(12), end: at(12, day: 22))
        let parts = UsageApportioner.split(slice, calendar: tokyo)
        #expect(parts.map(\.seconds) == [43200, 86400, 43200])
    }

    @Test func dstFallBackDayHas25Hours() {
        // America/New_York: 2026-11-01 has 25 hours
        let slice = UsageSlice(appID: "a", appName: "A",
                               start: at(0, day: 1, month: 11, cal: newYork),
                               end: at(0, day: 2, month: 11, cal: newYork))
        let parts = UsageApportioner.split(slice, calendar: newYork)
        #expect(parts.count == 1)
        #expect(parts[0].seconds == 25 * 3600)
        #expect(parts[0].day == UsageDay(year: 2026, month: 11, day: 1))
    }

    @Test func sliceEndingExactlyAtMidnightStaysOnOneDay() {
        let slice = UsageSlice(appID: "a", appName: "A", start: at(23), end: at(0, day: 21))
        let parts = UsageApportioner.split(slice, calendar: tokyo)
        #expect(parts.count == 1)
        #expect(parts[0].seconds == 3600)
    }

    @Test func accountantPlusApportionerAcrossMidnightWithSleep() {
        let out = run([
            .activate(appID: "a", name: "A", at: at(23, 50)),
            .sleep(at: at(0, 10, day: 21)),
            .wake(at: at(7, day: 21)),
            .stop(at: at(7, 5, day: 21)),
        ])
        var perDay: [UsageDay: TimeInterval] = [:]
        for slice in out.slices {
            for part in UsageApportioner.split(slice, calendar: tokyo) { perDay[part.day, default: 0] += part.seconds }
        }
        #expect(perDay[UsageDay(year: 2026, month: 10, day: 20)] == 600)
        #expect(perDay[UsageDay(year: 2026, month: 10, day: 21)] == 900)  // 0:00–0:10 + 7:00–7:05
    }

    @Test func dayKeyRoundTripsAndSteps() {
        let d = UsageDay(year: 2026, month: 3, day: 1)
        #expect(d.key == "2026-03-01")
        #expect(UsageDay(key: d.key) == d)
        #expect(UsageDay(key: "2026-13-01") == nil)
        #expect(UsageDay(key: "nope") == nil)
        #expect(d.adding(days: -1, calendar: tokyo) == UsageDay(year: 2026, month: 2, day: 28))
        #expect(UsageDay(year: 2026, month: 3, day: 7).adding(days: 1, calendar: newYork) == UsageDay(year: 2026, month: 3, day: 8))
    }

    @Test func retentionKeepsNinetyDaysIncludingToday() {
        let today = UsageDay(year: 2026, month: 10, day: 20)
        let cutoff = UsageDay.retentionCutoff(today: today, retentionDays: 90, calendar: tokyo)
        #expect(cutoff == UsageDay(year: 2026, month: 7, day: 23))
        #expect(UsageDay(year: 2026, month: 7, day: 22) < cutoff)
    }
}

@Suite("UsageSummary and UsageCSV")
struct UsageSummaryTests {
    let today = UsageDay(year: 2026, month: 10, day: 20)

    private func row(_ dayOffset: Int, _ app: String, _ seconds: TimeInterval) -> UsageDailyRow {
        UsageDailyRow(day: today.adding(days: dayOffset, calendar: tokyo), appID: app, appName: app.uppercased(), seconds: seconds)
    }

    @Test func summaryTopAppsWeekAndPickups() {
        let rows = (1...7).map { row(0, "app\($0)", TimeInterval($0) * 60) } + [row(-1, "app1", 3600), row(-8, "app1", 9999)]
        let s = UsageSummary.build(rows: rows, pickups: [today: 12], today: today, calendar: tokyo)
        #expect(s.todayTotal == TimeInterval((1...7).reduce(0, +)) * 60)
        #expect(s.topApps.map(\.appID) == ["app7", "app6", "app5", "app4", "app3"])
        #expect(s.week.count == 7)
        #expect(s.week.last?.day == today)
        #expect(s.week[5].seconds == 3600)
        #expect(!s.week.map(\.seconds).contains(9999))
        #expect(s.pickupsToday == 12)
    }

    @Test func summaryHidesExcludedApps() {
        let s = UsageSummary.build(rows: [row(0, "a", 60), row(0, "b", 120)], pickups: [:], today: today,
                                   excludedAppIDs: ["b"], calendar: tokyo)
        #expect(s.topApps.map(\.appID) == ["a"])
        #expect(s.todayTotal == 60)
    }

    @Test func csvQuotesAndOrders() {
        let rows = [
            UsageDailyRow(day: today, appID: "com.b", appName: "Say \"Hi\", Inc", seconds: 59.6),
            UsageDailyRow(day: today.adding(days: -1, calendar: tokyo), appID: "com.a", appName: "A", seconds: 10),
        ]
        let csv = UsageCSV.make(rows: rows, pickups: [today: 3])
        #expect(csv == """
        date,kind,bundle_id,app_name,seconds,count
        2026-10-19,app,com.a,A,10,
        2026-10-20,app,com.b,"Say ""Hi"", Inc",60,
        2026-10-20,pickups,,,,3

        """)
    }

    @Test func durationFormatting() {
        #expect(UsageFormatting.duration(0) == "0m")
        #expect(UsageFormatting.duration(20) == "<1m")
        #expect(UsageFormatting.duration(45 * 60) == "45m")
        #expect(UsageFormatting.duration(3 * 3600) == "3h")
        #expect(UsageFormatting.duration(3 * 3600 + 12 * 60 + 59) == "3h 12m")
    }
}
