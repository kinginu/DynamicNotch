// DEBUG-only commands of the Usage widget (2026-10-20), registered with DebugCommandRegistry
// by DebugHooks.install:
//   usagelog            log the tracker state and today's summary ("[Usage] …")
//   usageflush          store the open slice now and save
//   usagepreview:<dir>  write <dir>/usage-<live|sample|empty|off>-<dark|light>.png (the widget
//                       offscreen at 250 × 202 pt; `sample` = a fixed summary with installed Apple
//                       apps, `empty` = recording on but nothing today, `off` = recording off) and
//                       usage-settings-<dark|light>.png (Settings ▸ Widgets ▸ Usage at 520 pt).
// Previews never record or change settings.
#if DEBUG
import SwiftUI
import AppKit

extension DebugHooks {
    @MainActor static func registerUsageCommands() {
        DebugCommandRegistry.register("usagelog", "log the Usage tracker state and today's summary (read-only)") { _ in
            logUsage()
        }
        DebugCommandRegistry.register("usageflush", "store the Usage tracker's open slice now and save") { _ in
            UsageTracker.shared.flushNow()
        }
        DebugCommandRegistry.register("usagepreview", usage: "usagepreview:<dir>", "Usage widget live / sample / empty / off + settings") { arg in
            WidgetSnapshotter.session(arg, tag: "[Usage]") { usagePreview(to: $0) }
        }
    }

    @MainActor private static func logUsage() {
        let t = UsageTracker.shared
        let s = t.summary()
        NSLog("[Usage] running=%d enabled=%d today=%@ total=%.0fs pickups=%ld store=%@",
              t.isRunning, SettingsStore[.usageWidgetSettings].trackingEnabled, s.today.key,
              s.todayTotal, s.pickupsToday, UsageStore.storeURL.path)
        NSLog("[Usage]   %@", t.debugState)
        for app in s.topApps { NSLog("[Usage]   %@ (%@) %.0fs", app.appName, app.appID, app.seconds) }
        NSLog("[Usage]   week %@", s.week.map { "\($0.day.key)=\(Int($0.seconds))" }.joined(separator: " "))
    }

    @MainActor static func usageSample(now: Date = Date()) -> UsageSummary {
        let calendar = Calendar.current
        let today = UsageDay(now, calendar: calendar)
        let apps: [(String, String, TimeInterval)] = [
            ("com.apple.dt.Xcode", "Xcode", 2 * 3600 + 14 * 60),
            ("com.apple.Safari", "Safari", 58 * 60),
            ("com.apple.Terminal", "Terminal", 41 * 60),
            ("com.apple.mail", "Mail", 17 * 60),
            ("com.apple.Notes", "Notes", 6 * 60),
            ("com.apple.Music", "Music", 3 * 60),
        ]
        var rows = apps.map { UsageDailyRow(day: today, appID: $0.0, appName: $0.1, seconds: $0.2) }
        let past: [TimeInterval] = [4.2, 5.1, 2.4, 0.8, 6.3, 3.7]
        for (i, hours) in past.enumerated() {
            rows.append(UsageDailyRow(day: today.adding(days: i - 6, calendar: calendar), appID: "com.apple.Safari",
                                      appName: "Safari", seconds: hours * 3600))
        }
        return UsageSummary.build(rows: rows, pickups: [today: 23], today: today, calendar: calendar)
    }

    @MainActor private static func usagePreview(to dir: URL) {
        let calendar = Calendar.current
        let today = UsageDay(Date(), calendar: calendar)
        let empty = UsageSummary.build(rows: [], pickups: [today: 2], today: today, calendar: calendar)
        let cases: [(String, UsageSummary?, Bool?)] = [
            ("live", nil, nil), ("sample", usageSample(), true), ("empty", empty, true), ("off", nil, false),
        ]
        let width = NookWidgetLayout.cells(of: .usage) * NookWidgetLayout.cell
        for (name, summary, enabled) in cases {
            WidgetSnapshotter.widget("usage-\(name)", in: dir, width: width) {
                UsageWidgetView(previewSummary: summary, previewEnabled: enabled)
            }
        }
        WidgetSnapshotter.settings("usage-settings", in: dir, size: CGSize(width: WidgetSnapshotter.settingsWidth, height: 720)) {
            UsageWidgetSettingsView()
        }
    }
}
#endif
