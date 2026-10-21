// DEBUG-only commands of the World Clock widget (2026-10-20), registered with
// DebugCommandRegistry by DebugHooks.install:
//   worldclockpreview:<dir>   write <dir>/worldclock-<case>-<dark|light>.png (the widget offscreen
//                       at its grid width × 202 pt) for: live (stored settings, now), sample (this
//                       Mac + Tokyo, Cupertino, New York, London at 2026-10-20 09:23 UTC = 18:23 in
//                       Tokyo), sample12h, seconds-dial (seconds + analog dial), many (8 clocks),
//                       empty; and settings-<dark|light>.png (Settings ▸ Widgets ▸ World Clock).
// `installWorldClockHook()` (also still called when the widget appears) only re-registers.
// Nothing is written except the PNGs.
#if DEBUG
import SwiftUI
import AppKit

extension DebugHooks {
    @MainActor static func installWorldClockHook() {
        DebugCommandRegistry.register("worldclockpreview", usage: "worldclockpreview:<dir>",
                                      "World Clock widget live / sample / 12h / seconds-dial / many / empty + settings") { arg in
            WidgetSnapshotter.session(arg, tag: "[WorldClock]") { worldClockPreview(to: $0) }
        }
    }

    @MainActor private static func worldClockPreview(to dir: URL) {
        let sampleDate = Date(timeIntervalSince1970: 1_792_488_180) // 2026-10-20 09:23:00 UTC
        var sample = WorldClockWidgetSettings()
        sample.clocks = WorldClockWidgetSettings.defaultClocks()
        var twelve = sample
        twelve.hourFormat = .twelveHour
        var dial = sample
        dial.showSeconds = true
        dial.showAnalogDial = true
        var many = sample
        many.clocks = ["Asia/Tokyo", "America/Los_Angeles", "America/New_York", "Europe/London",
                       "Asia/Kolkata", "Australia/Sydney", "America/Sao_Paulo", "Pacific/Auckland"]
            .map { WorldClock(timeZoneID: $0) }
        many.clocks[1].label = "Cupertino"
        var empty = sample
        empty.clocks = []

        let cases: [(String, WorldClockWidgetSettings?, Date?)] = [
            ("live", nil, nil), ("sample", sample, sampleDate), ("sample12h", twelve, sampleDate),
            ("seconds-dial", dial, sampleDate.addingTimeInterval(37)), ("many", many, sampleDate), ("empty", empty, nil),
        ]
        for (name, settings, date) in cases {
            let s = settings ?? SettingsStore[.worldClocksWidgetSettings]
            let width = (WorldClockWidgetLayout.width(count: s.clocks.count, showSeconds: s.showSeconds)).rounded()
            WidgetSnapshotter.widget("worldclock-\(name)", in: dir, width: width) {
                WorldClockWidgetView(previewDate: date, previewSettings: settings)
            }
        }
        WidgetSnapshotter.settings("settings", in: dir, size: CGSize(width: 560, height: 760)) { WorldClockWidgetSettingsView() }
        NSLog("[WorldClock] cells(live)=%.2f", WorldClockWidgetLayout.preferredCells())
    }
}
#endif
