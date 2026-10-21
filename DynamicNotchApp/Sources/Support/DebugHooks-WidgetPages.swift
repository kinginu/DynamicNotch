// F9 (widget pages): DEBUG-only commands for pages and drag-to-reorder, registered with
// DebugCommandRegistry by DebugHooks.install (also re-registered, idempotently, when a grid appears).
// The grid commands need an open notch (`open`).
//   pages:<a,b|c|>            set the pages (raw values; `|` separates pages, an empty part = empty page)
//   page:<n|next|prev>        show page n (0-based)
//   pagesstate                log stored widgets / widgetPages, the current page, the drag, and per grid
//                             its window, frame and cell frames
//   widgetdrag:[alt@]<x,y>;…  synthetic press (alt@: with ⌥) at the first point (grid coordinates of the open notch on
//                             the main screen), then for each token: `x,y` moves there in 8 steps,
//                             `w<seconds>` waits, `/<dir>` snapshots the windows, `esc` presses
//                             Escape; released at the end.
//                             Hold still first (`w0.6`) to lift.
//   widgetclick:<x,y>         synthetic click (press + release) at a grid point
//   widgetswipe:<dx>[,<steps>[,<hold s>]] trackpad swipe (began / changed × steps / ended) over the grid;
//                             with a hold, the pointer is reported outside the notch meanwhile
//   widgetwheel:<dx>          one mouse-wheel tick with a horizontal delta
//   widgetkey:<left|right|esc>
//   appearance:<dark|light|system>  NSApp.appearance (settings snapshots)
//   settingsshot:<dir>        open Settings ▸ Nook ▸ Widgets, move it off screen, snapshot <dir>/dark, <dir>/light
#if DEBUG
import AppKit
import SwiftUI

extension NookGridInteraction {
    /// Live grids (one per open notch window).
    static let live = NSHashTable<NookGridInteraction>.weakObjects()
}

enum NookWidgetPagesDebug {
    private static let commands: [(name: String, usage: String, summary: String)] = [
        ("pages", "pages:<a,b|c|>", "set the Nook widget pages (raw values; | separates pages, empty part = empty page)"),
        ("page", "page:<n|next|prev>", "show Nook page n (0-based)"),
        ("pagesstate", "pagesstate", "log widgets / widgetPages / current page / drag and each grid's cell frames"),
        ("widgetdrag", "widgetdrag:[alt@]<x,y>;<x,y|w<s>|/<dir>|esc>;…", "synthetic press-drag in the open notch's grid (alt@ = ⌥-press; else hold w0.6 on a header to lift)"),
        ("widgetclick", "widgetclick:<x,y>", "synthetic click at a grid point of the open notch"),
        ("widgetswipe", "widgetswipe:<dx>[,<steps>[,<hold s>]]", "trackpad swipe over the grid (hold: pointer reported outside meanwhile)"),
        ("widgetwheel", "widgetwheel:<dx>", "one mouse-wheel tick with a horizontal delta over the grid"),
        ("widgetkey", "widgetkey:<left|right|esc>", "page / cancel-drag key in the open notch"),
        ("appearance", "appearance:<dark|light|system>", "set NSApp.appearance"),
        ("settingsshot", "settingsshot:<dir>", "Settings ▸ Nook ▸ Widgets off screen, PNGs in <dir>/dark and <dir>/light"),
    ]

    @MainActor static func install() {
        for c in commands {
            let name = c.name
            DebugCommandRegistry.register(name, usage: c.usage, c.summary) { arg in handle(name, arg) }
        }
    }

    /// The grid on the main screen's notch window (else any).
    @MainActor private static var grid: NookGridInteraction? {
        let all = NookGridInteraction.live.allObjects
        return all.first { $0.window?.screen == NSScreen.main } ?? all.first
    }

    @MainActor private static func handle(_ verb: String, _ arg: String) {
        let pager = NookWidgetPager.shared
        switch verb {
        case "pages":
            let pages = arg.split(separator: "|", omittingEmptySubsequences: false).map { part in
                part.split(separator: ",").compactMap { NookWidget(rawValue: String($0)) }
            }
            SettingsStore[.nookSettings].pages = pages
            log("pages set")
        case "page":
            let count = pager.pages(SettingsStore[.nookSettings]).count
            let current = pager.pageIndex(count: count)
            let target = arg == "next" ? current + 1 : arg == "prev" ? current - 1 : (Int(arg) ?? current)
            pager.show(page: target, count: count)
            after(0.6) { log("page \(arg)") }
        case "pagesstate":
            log("state")
        case "widgetdrag":
            drag(arg)
        case "widgetclick":
            guard let g = grid, let p = point(arg) else { return }
            post(.leftMouseDown, at: p, in: g)
            post(.leftMouseUp, at: p, in: g)
            after(0.3) { log("click") }
        case "widgetswipe":
            guard let g = grid else { return }
            let parts = arg.split(separator: ",").compactMap { Double($0) }
            guard let dx = parts.first else { return }
            let steps = parts.count > 1 ? Int(parts[1]) : 10
            let at = CGPoint(x: g.gridFrame.width / 2, y: 100)
            _ = g.scrollWheel(.init(dx: 0, dy: 0, precise: true, phase: .began), at: at)
            var used = false
            for i in 0..<steps {
                let step = CGFloat(dx) / CGFloat(steps)
                // spread over time so the velocity estimate is realistic (~120 Hz)
                after(Double(i) / 120) {
                    used = g.scrollWheel(.init(dx: step, dy: 0, precise: true, phase: .changed), at: at) || used
                }
            }
            // optional third value: keep the fingers down that long with the pointer reported
            // outside the notch (hoverprobe:out) — the notch must stay open while swiping
            let hold = parts.count > 2 ? parts[2] : 0
            let mid = Double(steps) / 120 + 0.02
            if hold > 0 {
                after(mid) {
                    DistributedNotificationCenter.default().postNotificationName(DebugHooks.notificationName, object: "hoverprobe:out",
                                                                                 userInfo: nil, deliverImmediately: true)
                }
                after(mid + hold) { NSLog("[WidgetPages] swipe held %.1fs: mode=%@", hold, DynamicNotchState.shared.mode.rawValue) }
            }
            after(mid + hold) {
                NSLog("[WidgetPages] swipe mid offset=%.1f claimed=%d", pager.swipeOffset, used ? 1 : 0)
                _ = g.scrollWheel(.init(dx: 0, dy: 0, precise: true, phase: .ended), at: at)
            }
            after(mid + hold + 1.2) { log("swipe \(arg) mode=\(DynamicNotchState.shared.mode.rawValue)") }
        case "widgetwheel":
            guard let g = grid, let dx = Double(arg) else { return }
            let used = g.scrollWheel(.init(dx: CGFloat(dx), dy: 0, precise: false, phase: []), at: CGPoint(x: g.gridFrame.width / 2, y: 100))
            after(0.6) { log("wheel \(arg) used=\(used)") }
        case "widgetkey":
            guard let g = grid else { return }
            let code: UInt16 = arg == "left" ? 123 : arg == "right" ? 124 : 53
            let used = g.handleKey(code)
            after(0.6) { log("key \(arg) used=\(used)") }
        case "appearance":
            NSApp.appearance = arg == "dark" ? NSAppearance(named: .darkAqua) : arg == "light" ? NSAppearance(named: .aqua) : nil
        case "settingsshot":
            // Settings ▸ Nook ▸ Widgets, moved off screen at once (development instance), in dark then light
            NookSettingsNavigation.shared.tab = .widgets
            WindowsManager.shared.showSettings(pane: AppSettings.PaneIdentifier("nook"))
            let dir = URL(fileURLWithPath: arg)
            func offscreen() {
                for w in NSApp.windows where w.isVisible && !w.title.isEmpty { w.setFrameOrigin(NSPoint(x: -20_000, y: 200)) }
            }
            after(0.05) { offscreen() }
            after(0.4) { offscreen(); NSApp.appearance = NSAppearance(named: .darkAqua) }
            after(1.2) { DebugHooks.snapshot(to: dir.appendingPathComponent("dark")); NSApp.appearance = NSAppearance(named: .aqua) }
            after(2.0) { DebugHooks.snapshot(to: dir.appendingPathComponent("light")); NSApp.appearance = nil; NSLog("[WidgetPages] settingsshot done") }
        default:
            break
        }
    }

    // MARK: Synthetic drag

    @MainActor private static func drag(_ arg: String) {
        guard let g = grid else { NSLog("[WidgetPages] widgetdrag: no open grid"); return }
        let tokens = arg.split(separator: ";").map(String.init)
        // `alt@x,y` as the first token: the press is made with ⌥ held
        let alt = tokens.first?.hasPrefix("alt@") ?? false
        guard let first = tokens.first.map({ alt ? String($0.dropFirst(4)) : $0 }).flatMap(point) else { return }
        post(.leftMouseDown, at: first, in: g, modifiers: alt ? [.option] : [])
        var t: TimeInterval = 0
        var last = first
        for token in tokens.dropFirst() {
            if token == "esc" {
                after(t) { _ = g.handleKey(53) }   // Escape during the drag
            } else if token.hasPrefix("/") {
                after(t) { DebugHooks.snapshot(to: URL(fileURLWithPath: token)) }   // mid-drag snapshot
            } else if token.hasPrefix("w"), let s = Double(token.dropFirst()) {
                t += s
                let at = last, until = t
                // AppKit sends mouse-dragged events only on movement; a hold sends none
                after(t) { NSLog("[WidgetPages] drag waited to %.2f at %@ lifted=%@", until, NSStringFromPoint(at), NookWidgetPager.shared.dragged?.rawValue ?? "-") }
            } else if let p = point(token) {
                let from = last
                for i in 1...8 {
                    t += 0.016
                    let q = CGPoint(x: from.x + (p.x - from.x) * CGFloat(i) / 8, y: from.y + (p.y - from.y) * CGFloat(i) / 8)
                    after(t) { post(.leftMouseDragged, at: q, in: g) }
                }
                last = p
            }
        }
        let end = last
        after(t + 0.05) {
            NSLog("[WidgetPages] before release: dragged=%@ draft=%@", pager.dragged?.rawValue ?? "-", describe(pager.draftPages))
            post(.leftMouseUp, at: end, in: g)
        }
        after(t + 0.6) { log("drag done") }
    }

    @MainActor private static var pager: NookWidgetPager { .shared }

    private static func point(_ s: String) -> CGPoint? {
        let v = s.split(separator: ",").compactMap { Double($0) }
        return v.count == 2 ? CGPoint(x: v[0], y: v[1]) : nil
    }

    /// Post a mouse event at a grid point of `g` through NSApp.sendEvent (the local monitors see it).
    @MainActor private static func post(_ type: NSEvent.EventType, at p: CGPoint, in g: NookGridInteraction,
                                        modifiers: NSEvent.ModifierFlags = []) {
        guard let window = g.window else { return }
        let h = window.contentView?.bounds.height ?? window.frame.height
        let loc = NSPoint(x: g.gridFrame.minX + p.x, y: h - (g.gridFrame.minY + p.y))
        guard let e = NSEvent.mouseEvent(with: type, location: loc, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                                         pressure: type == .leftMouseUp ? 0 : 1) else { return }
        NSApp.sendEvent(e)
    }

    private static func after(_ s: TimeInterval, _ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + s) { MainActor.assumeIsolated { block() } }
    }

    private static func describe(_ pages: [[NookWidget]]?) -> String {
        guard let pages else { return "nil" }
        return pages.map { $0.map(\.rawValue).joined(separator: ",") }.joined(separator: " | ")
    }

    @MainActor private static func log(_ what: String) {
        let s = SettingsStore[.nookSettings]
        let pager = NookWidgetPager.shared
        NSLog("[WidgetPages] %@: widgets=%@ widgetPages=%@ pages=%@ current=%d dragged=%@ draft=%@ interacting=%d",
              what, s.widgets.map(\.rawValue).joined(separator: ","), describe(s.widgetPages), describe(s.pages),
              pager.currentPage, pager.dragged?.rawValue ?? "-", describe(pager.draftPages), pager.isInteracting ? 1 : 0)
        for g in NookGridInteraction.live.allObjects {
            let geo = g.geometry()
            let cells = geo.pages.indices.flatMap { p in geo.pages[p].indices.map { i in
                "\(geo.pages[p][i].rawValue)@p\(p):\(Int(geo.cellFrame(page: p, index: i).minX))+\(Int(geo.cellFrame(page: p, index: i).width))" } }
            NSLog("[WidgetPages]   grid window=%@ gridFrame=%@ container=%.0f pageWidths=%@ cells=%@",
                  NSStringFromRect(g.window?.frame ?? .zero), NSStringFromRect(g.gridFrame), g.containerWidth,
                  geo.pageWidths.map { String(Int($0)) }.joined(separator: ","), cells.joined(separator: " "))
        }
    }
}
#endif
