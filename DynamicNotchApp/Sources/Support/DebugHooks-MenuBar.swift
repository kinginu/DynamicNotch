// DEBUG-only commands of the Menu Bar widget (2026-10-20), registered with
// DebugCommandRegistry by DebugHooks.install (`MenuBarItemsDebug.install()`, also still called by
// MenuBarItemsManager.start(), only re-registers).
//   mblog               refresh and log the separator frame, every status window on its row, the
//                       hidden items (owner, frame, image size) and the permission states
//   mbtestitem:on|off   add/remove a test status item ("DN-test") of this process. It is created
//                       after the separator, so it sits to its LEFT (= hidden when collapsed); its
//                       click action logs "[MenuBar] test item clicked". Lets the hide / capture /
//                       click path be tested without touching other apps' items.
//   mbreveal:on|off     same as the widget's show/hide button
//   mbclicktest[:right] forward a click to the test item (refuses any other item)
//   mbpreview:<dir>     write <dir>/menubar-<state>-<dark|light>.png (widget offscreen, 250 × 202 pt)
//                       for live / sample / sample-noscreen / sample-noax / empty / off, and
//                       settings-<dark|light>.png
#if DEBUG
import SwiftUI
import AppKit

@MainActor
enum MenuBarItemsDebug {
    static func install() {
        let verbs: [(String, String?, String)] = [
            ("mblog", nil, "refresh and log the separator, the status windows on its row, the hidden items, permissions"),
            ("mbtestitem", "mbtestitem:on|off", "add/remove this process's test status item \"DN-test\""),
            ("mbreveal", "mbreveal:on|off", "same as the widget's show/hide button"),
            ("mbclicktest", "mbclicktest[:right]", "forward a click to the test item (refuses any other item)"),
            ("mbpreview", "mbpreview:<dir>", "Menu Bar widget live / sample / no-permission / empty / off + settings"),
        ]
        for (verb, usage, summary) in verbs {
            DebugCommandRegistry.register(verb, usage: usage, summary) { arg in handle(arg.isEmpty ? verb : verb + ":" + arg) }
        }
    }

    private static let testTarget = TestTarget()

    final class TestTarget: NSObject {
        @MainActor @objc func clicked(_ sender: Any?) {
            NSLog("[MenuBar] test item clicked (event type %ld)", NSApp.currentEvent?.type.rawValue ?? -1)
        }
    }

    static func handle(_ command: String) {
        let (verb, arg): (String, String) = {
            guard let i = command.firstIndex(of: ":") else { return (command, "") }
            return (String(command[..<i]), String(command[command.index(after: i)...]))
        }()
        let m = MenuBarItemsManager.shared
        switch verb {
        case "mblog":
            m.refresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { log() }
        case "mbtestitem":
            if arg == "off" {
                if let item = m.debugTestItem { NSStatusBar.system.removeStatusItem(item) }
                m.debugTestItem = nil
            } else if m.debugTestItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.button?.image = NSImage(systemSymbolName: "ladybug.fill", accessibilityDescription: "DN-test")
                item.button?.target = testTarget
                item.button?.action = #selector(TestTarget.clicked(_:))
                item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
                m.debugTestItem = item
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { m.refresh(); log() }
        case "mbreveal":
            m.setShowHiddenItems(arg != "off")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { m.refresh(); log() }
        case "mbclicktest":
            guard let test = m.debugTestItem?.button?.window?.frame else { NSLog("[MenuBar] no test item"); return }
            m.refresh()
            // The test item's window: the hidden item at the test item's own frame.
            let cg = MenuBarItemsManager.cgRect(fromAppKit: test)
            guard let item = m.hiddenItems.first(where: { abs($0.frame.minX - cg.minX) < 1.5 && abs($0.frame.width - cg.width) < 1.5 }) else {
                NSLog("[MenuBar] test item is not among the hidden items; hidden=%@", m.hiddenItems.map { "\($0.windowID)@\(Int($0.frame.minX))" }.joined(separator: ","))
                return
            }
            m.activate(item, rightClick: arg == "right")
        case "mbpreview":
            m.refresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                WidgetSnapshotter.session(arg, tag: "[MenuBar]") { preview(to: $0) }
            }
        default:
            NSLog("[MenuBar] unknown command %@", command)
        }
    }

    static func log() {
        let m = MenuBarItemsManager.shared
        NSLog("[MenuBar] separatorActive=%d revealed=%d sep=%@ screenRecording=%d accessibility=%d scale=%.1f captureError=%@",
              m.separatorActive, m.isRevealed, m.separatorFrameCG.map { NSStringFromRect($0) } ?? "nil",
              m.screenRecordingGranted, m.accessibilityGranted, m.displayScale, m.captureError ?? "-")
        if let sep = m.separatorFrameCG {
            let row = MenuBarItemsManager.statusWindows().filter { abs($0.frame.minY - sep.minY) < 2 }.sorted { $0.frame.minX < $1.frame.minX }
            for w in row {
                NSLog("[MenuBar] row %u x=%.0f w=%.0f title=%@ onScreen=%d", w.id, w.frame.minX, w.frame.width, w.title, w.onScreen)
            }
        }
        NSLog("[MenuBar] hidden=%ld visible=%ld", m.hiddenItems.count, m.visibleItemCount)
        for item in m.hiddenItems {
            let img = m.images[item.windowID]
            NSLog("[MenuBar] hidden %u %@ (%@) frame=%@ image=%@", item.windowID, item.appName, item.bundleID ?? "-",
                  NSStringFromRect(item.frame), img.map { "\($0.width)x\($0.height) lum=\(String(format: "%.2f", MenuBarItemsManager.luminance($0)))" } ?? "none")
        }
    }

    // MARK: Previews

    private static func sampleImage(symbol: String, width: CGFloat, dark: Bool) -> CGImage? {
        let size = NSSize(width: width, height: 30)
        let image = NSImage(size: size, flipped: false) { rect in
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            guard let s = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return false }
            let tinted = NSImage(size: s.size, flipped: false) { r in
                s.draw(in: r)
                (dark ? NSColor.black : NSColor.white).set()
                r.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(x: (rect.width - s.size.width) / 2, y: (rect.height - s.size.height) / 2,
                                   width: s.size.width, height: s.size.height))
            return true
        }
        var rect = NSRect(origin: .zero, size: NSSize(width: width * 2, height: 60))
        return image.cgImage(forProposedRect: &rect, context: nil, hints: [.ctm: AffineTransform(scale: 2)])
    }

    private static var sample: (items: [MenuBarItem], images: [CGWindowID: CGImage]) {
        let entries: [(String, String?, String, CGFloat)] = [
            ("OneDrive", "com.microsoft.OneDrive-mac", "cloud", 36), ("Bitwarden", "com.bitwarden.desktop", "lock.shield", 32),
            ("Rectangle", "com.knollsoft.Rectangle", "rectangle.split.2x1", 38), ("Raycast", "com.raycast.macos", "command", 32),
            ("Tailscale", "io.tailscale.ipn.macos", "point.3.connected.trianglepath.dotted", 38),
            ("Weather", "com.apple.weather.menu", "cloud.sun", 72), ("MonitorControl", "app.monitorcontrol.MonitorControl", "sun.max", 36),
        ]
        var items: [MenuBarItem] = []
        var images: [CGWindowID: CGImage] = [:]
        var x: CGFloat = 2000
        for (i, e) in entries.enumerated() {
            let id = CGWindowID(90_000 + i)
            items.append(MenuBarItem(windowID: id, frame: CGRect(x: x, y: 0, width: e.3, height: 30), title: e.1 ?? "", bundleID: e.1, appName: e.0))
            images[id] = sampleImage(symbol: e.2, width: e.3, dark: i == 2)  // one dark (light-menu-bar) icon
            x += e.3
        }
        return (items, images)
    }

    static func preview(to dir: URL) {
        log()
        let s = sample
        let states: [(String, MenuBarItemsPreviewState?)] = [
            ("live", nil),
            ("sample", MenuBarItemsPreviewState(items: s.items, images: s.images)),
            ("sample-noscreen", MenuBarItemsPreviewState(items: s.items, screenRecording: false)),
            ("sample-noax", MenuBarItemsPreviewState(items: s.items, images: s.images, accessibility: false)),
            ("empty", MenuBarItemsPreviewState(items: [])),
            ("off", MenuBarItemsPreviewState(items: [], separatorActive: false)),
        ]
        let width = NookWidgetLayout.width(of: .menuBarItems)
        for (name, state) in states {
            WidgetSnapshotter.widget("menubar-\(name)", in: dir, width: width, height: NookWidgetLayout.cellHeight) {
                MenuBarItemsWidgetView(preview: state)
            }
        }
        WidgetSnapshotter.settings("settings", in: dir, size: CGSize(width: 560, height: 900), background: false) {
            MenuBarItemsWidgetSettingsView()
        }
    }
}
#endif
