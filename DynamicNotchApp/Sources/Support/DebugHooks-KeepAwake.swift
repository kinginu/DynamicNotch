// DEBUG-only commands of the Keep Awake widget (2026-10-20), registered with
// DebugCommandRegistry by DebugHooks.install (`KeepAwakeDebugHooks.install()`, also still called by
// KeepAwakeManager.start(), only re-registers).
//   kapreview:<dir>   write <dir>/keepawake-<off|15m|2h|infinite|display>-<dark|light>.png (the widget
//                     offscreen at 200 × 202 pt, preview state: no assertion, nothing stored),
//                     keepawake-notch-<15m|2h|infinite>.png (the closed-notch live activity on a
//                     mock notch) and keepawake-settings-<dark|light>.png (520 pt).
//   katest            create an assertion of each type for 3 s (not persisted) and log
//                     `pmset -g assertions` lines naming it, then release.
//   kalive:<seconds>  run a real session of <seconds> that is never written to UserDefaults
//                     (live activity + assertion), `kalive:off` ends it. `kastate` logs the state.
#if DEBUG
import SwiftUI
import AppKit
import IOKit.pwr_mgt

@MainActor
enum KeepAwakeDebugHooks {
    static func install() {
        let r = DebugCommandRegistry.self
        r.register("kapreview", usage: "kapreview:<dir>", "Keep Awake widget states, closed-notch activity, settings (preview state only)") { arg in
            WidgetSnapshotter.session(arg, tag: "[KeepAwake]") { preview(to: $0) }
        }
        r.register("katest", "create each assertion type briefly, log pmset lines, release") { _ in assertionTest() }
        r.register("kastate", "log the Keep Awake state and its pmset assertions") { _ in logState() }
        r.register("kalive", usage: "kalive:<seconds>|off", "run a real, unpersisted session (live activity + assertion) / end it") { arg in
            let m = KeepAwakeManager.shared
            if arg == "off" { m.deactivate() } else {
                m.persists = false
                let secs = TimeInterval(arg) ?? 90
                m.debugBegin(seconds: secs)
            }
            logState()
        }
    }

    private static func logState() {
        let m = KeepAwakeManager.shared
        NSLog("%@", "[KeepAwake] active=\(m.isActive) end=\(m.session?.endDate.map { "\($0)" } ?? "nil") assertion=\(m.debugAssertionID) systemOnly=\(m.holdsSystemOnlyAssertion) error=\(m.lastError ?? "nil") la=\(LiveActivityCenter.shared.debugDescription)")
        let out = pmsetAssertions().split(separator: "\n").filter { $0.contains("Keep Awake") }.joined(separator: " || ")
        NSLog("%@", "[KeepAwake] pmset: \(out.isEmpty ? "(none)" : out)")
    }

    private static func pmsetAssertions() -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["-g", "assertions"]
        let pipe = Pipe()
        p.standardOutput = pipe
        try? p.run()
        p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private static func assertionTest() {
        for (label, type) in [("display", kIOPMAssertionTypePreventUserIdleDisplaySleep), ("system", kIOPMAssertionTypePreventUserIdleSystemSleep)] {
            var id = IOPMAssertionID(kIOPMNullAssertionID)
            let r = IOPMAssertionCreateWithDescription(type as CFString, "DynamicNotch Keep Awake test" as CFString,
                                                       "katest \(label)" as CFString, nil, nil, 10,
                                                       kIOPMAssertionTimeoutActionRelease as CFString, &id)
            NSLog("%@", "[KeepAwake] katest \(label): result=\(r) id=\(id)")
            let lines = pmsetAssertions().split(separator: "\n").filter { $0.contains("Keep Awake test") }
            NSLog("%@", "[KeepAwake] katest \(label) pmset: \(lines.joined(separator: " || "))")
            IOPMAssertionRelease(id)
        }
        let after = pmsetAssertions().split(separator: "\n").filter { $0.contains("Keep Awake test") }
        NSLog("%@", "[KeepAwake] katest after release: \(after.isEmpty ? "(none)" : after.joined(separator: " || "))")
    }

    private static func preview(to dir: URL) {
        let now = Date()
        func s(_ d: KeepAwakeDuration, elapsed: TimeInterval) -> KeepAwakeManager.Session {
            let start = now.addingTimeInterval(-elapsed)
            return .init(duration: d, started: start, endDate: d.seconds.map { start.addingTimeInterval($0) })
        }
        let states: [(String, KeepAwakePreviewState)] = [
            ("off", .init(session: nil, allowDisplaySleep: false, now: now)),
            ("15m", .init(session: s(.fifteenMinutes, elapsed: 4 * 60 + 23), allowDisplaySleep: false, now: now)),
            ("2h", .init(session: s(.twoHours, elapsed: 25 * 60), allowDisplaySleep: false, now: now)),
            ("infinite", .init(session: s(.indefinite, elapsed: 0), allowDisplaySleep: false, now: now)),
            ("display", .init(session: s(.oneHour, elapsed: 10 * 60), allowDisplaySleep: true, now: now)),
        ]
        for (name, state) in states {
            WidgetSnapshotter.widget("keepawake-\(name)", in: dir, width: 200) { KeepAwakeWidgetView(preview: state) }
        }
        // closed notch: side | camera housing (black, 185 × 32) | side
        for (name, state, side) in [("15m", states[1].1, CGFloat(54)), ("2h", states[2].1, CGFloat(66)), ("infinite", states[3].1, CGFloat(40))] {
            let notch = CGSize(width: 185, height: 32)
            let view = HStack(spacing: 0) {
                KeepAwakeLiveActivityView(side: .leading, preview: state)
                    .padding(.leading, ClosedNotchActivityLayout.outerInset).padding(.trailing, 4)
                    .frame(width: side, height: notch.height, alignment: .leading)
                Color.clear.frame(width: notch.width, height: notch.height)
                KeepAwakeLiveActivityView(side: .trailing, preview: state)
                    .padding(.trailing, ClosedNotchActivityLayout.outerInset).padding(.leading, 4)
                    .frame(width: side, height: notch.height, alignment: .trailing)
            }
            .background(UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10).fill(Color.black))
            .padding(16)
            .background(Color(white: 0.55))
            .environment(\.colorScheme, .dark)
            WidgetSnapshotter.write(view, size: CGSize(width: notch.width + 2 * side + 32, height: notch.height + 32), dark: true,
                                    to: dir.appendingPathComponent("keepawake-notch-\(name).png"))
        }
        WidgetSnapshotter.settings("keepawake-settings", in: dir, size: CGSize(width: 520, height: 520)) { KeepAwakeWidgetSettingsView() }
    }
}

extension KeepAwakeManager {
    /// DEBUG `kalive`: a timed session of `seconds` (not persisted; `persists` is already false).
    func debugBegin(seconds: TimeInterval) {
        debugStart(Session(duration: .fifteenMinutes, started: Date(), endDate: Date().addingTimeInterval(seconds)))
    }
}
#endif
