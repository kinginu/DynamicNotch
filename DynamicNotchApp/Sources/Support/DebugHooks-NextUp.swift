// DEBUG-only commands of the Next Up widget (2026-10-20), registered with DebugCommandRegistry
// by DebugHooks.install (`NextUpDebug.install()`, also still called by NextUpManager.start, only
// re-registers).
//   nextuplog            log access, the fetched events and the activity state ("[NextUp] …")
//   nextupforce          force the closed-notch activity with a synthetic event starting in 5 min
//   nextupclear          drop the forced activity
//   nextuppreview:<dir>  write <dir>/nextup-<sample|live|empty>-<dark|light>.png (the widget offscreen
//                        at its grid width × 202 pt; `sample` = three synthetic events incl. one in
//                        progress with a Zoom link and one starting in 4 min), nextup-activity.png
//                        (the closed-notch activity sides around a mock camera housing) and
//                        nextup-settings-<dark|light>.png (Settings ▸ Widgets ▸ Next Up at 520 pt).
#if DEBUG
import SwiftUI
import AppKit

@MainActor
enum NextUpDebug {
    static func install() {
        let verbs: [(String, String?, String)] = [
            ("nextuplog", nil, "refresh and log access, the fetched events and the activity state"),
            ("nextupforce", nil, "force the closed-notch activity with a synthetic event in ~5 min"),
            ("nextupclear", nil, "drop the forced activity"),
            ("nextuppreview", "nextuppreview:<dir>", "Next Up widget sample / live / empty, closed-notch activity, settings"),
        ]
        for (verb, usage, summary) in verbs {
            DebugCommandRegistry.register(verb, usage: usage, summary) { arg in handle(arg.isEmpty ? verb : verb + ":" + arg) }
        }
    }

    static func handle(_ command: String) {
        let (verb, arg): (String, String) = {
            guard let i = command.firstIndex(of: ":") else { return (command, "") }
            return (String(command[..<i]), String(command[command.index(after: i)...]))
        }()
        let manager = NextUpManager.shared
        switch verb {
        case "nextuplog":
            manager.refresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { log() }
        case "nextupforce":
            manager.debugSetActivity(sample(now: Date())[1])
            log()
        case "nextupclear":
            manager.debugSetActivity(nil)
            log()
        case "nextuppreview":
            manager.refresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                WidgetSnapshotter.session(arg, tag: "[NextUp]") { preview(to: $0) }
            }
        default:
            break
        }
    }

    private static func log() {
        let m = NextUpManager.shared
        NSLog("[NextUp] access=%d status=%ld items=%ld activity=%@ requested=%@",
              m.hasAccess, CalendarManager.shared.authorizationStatus.rawValue, m.items.count,
              m.activityItem?.title ?? "nil",
              ActiveLiveActivitiesManager.shared.requestedActivities.map(\.rawValue).sorted().description)
        for item in m.items {
            NSLog("[NextUp]  %@ | %@ – %@ | %@ | join=%@", item.title, item.start.description, item.end.description,
                  item.calendarTitle, item.meeting?.url.absoluteString ?? "-")
        }
    }

    static func sample(now: Date) -> [NextUpItem] {
        let n = now
        return [
            NextUpItem(id: "s1", title: "Design review", start: n.addingTimeInterval(-37 * 60), end: n.addingTimeInterval(23 * 60),
                       isAllDay: false, location: "https://zoom.us/j/123456789", calendarTitle: "Work", color: .blue,
                       meeting: NextUpMeetingLink.find(in: ["Join: https://us02web.zoom.us/j/123456789?pwd=abc."])),
            NextUpItem(id: "s2", title: "1:1 with Sam", start: n.addingTimeInterval(4 * 60 + 20), end: n.addingTimeInterval(34 * 60),
                       isAllDay: false, location: "Room 4B", calendarTitle: "Work", color: .orange,
                       meeting: NextUpMeetingLink.find(in: [nil, "Room 4B", "https://meet.google.com/abc-defg-hij"])),
            NextUpItem(id: "s3", title: "Dentist", start: n.addingTimeInterval(3 * 3600 + 10 * 60), end: n.addingTimeInterval(4 * 3600),
                       isAllDay: false, location: "Main Street 12", calendarTitle: "Personal", color: .green, meeting: nil),
        ]
    }

    private static func preview(to dir: URL) {
        log()
        let now = Date()
        let width = NookWidgetLayout.width(of: .nextUp)
        let cases: [(String, [NextUpItem]?)] = [("sample", sample(now: now)), ("live", nil), ("empty", [])]
        for (name, items) in cases {
            WidgetSnapshotter.widget("nextup-\(name)", in: dir, width: width) {
                NextUpWidgetView(previewItems: items, previewNow: items == nil ? nil : now, previewActivity: name == "sample")
            }
        }
        // closed-notch activity (synthetic event in 5 min), sides as ClosedNotchActivitiesView sizes them
        let hadDebug = NextUpManager.shared.debugActivity
        NextUpManager.shared.debugSetActivity(sample(now: now)[1])
        let notch = CGSize(width: 185, height: 32)
        let side = ClosedNotchActivityLayout.width(for: .nextUp, notchHeight: notch.height)
        let activity = HStack(spacing: 0) {
            NextUpLiveActivityView(side: .leading)
                .padding(.leading, ClosedNotchActivityLayout.outerInset).padding(.trailing, 4)
                .frame(width: side, height: notch.height, alignment: .leading)
            Color.clear.frame(width: notch.width, height: notch.height)
            NextUpLiveActivityView(side: .trailing)
                .padding(.trailing, ClosedNotchActivityLayout.outerInset).padding(.leading, 4)
                .frame(width: side, height: notch.height, alignment: .trailing)
        }
        .background(UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12).fill(Color.black))
        .padding(20)
        .background(Color.gray)
        .environment(\.colorScheme, .dark)
        WidgetSnapshotter.write(activity, size: CGSize(width: notch.width + 2 * side + 40, height: notch.height + 40), dark: true,
                                to: dir.appendingPathComponent("nextup-activity.png"))
        NextUpManager.shared.debugSetActivity(hadDebug)
        WidgetSnapshotter.settings("nextup-settings", in: dir, size: CGSize(width: 520, height: 640)) { NextUpWidgetSettingsView() }
    }
}
#endif
