// DEBUG probes for the notch hover state machine and window geometry (NotchHover.swift),
// registered by `NotchInteractionMonitor.install()`.
import AppKit
import SwiftUI

#if DEBUG
extension NotchInteractionMonitor {
    /// DEBUG (distributed notification on `DebugHooks.notificationName`): `hoverprobe:in|out|stop|state`.
    /// `in` simulates the pointer entering every closed notch and logs the mode 0.5 s later,
    /// `out` the pointer leaving, `stop` stops all ringing timers, `state` logs the suppression.
    static func installDebugHoverProbe() {
        installDebugGeometryProbe()
        _ = DistributedNotificationCenter.default().addObserver(forName: DebugHooks.notificationName, object: nil, queue: .main) { note in
            guard let command = note.object as? String, command.hasPrefix("hoverprobe:") else { return }
            let arg = String(command.dropFirst("hoverprobe:".count))
            MainActor.assumeIsolated {
                @MainActor func log(_ what: String) {
                    for (id, kit) in WindowsManager.shared.displayKits {
                        let vm = kit.dynamicnotchWindow.flatMap { NotchViewModel.debugByWindow.object(forKey: $0) }
                        NSLog("[DebugHooks] hoverprobe %@ screen %u: mode=%@ hovering=%d suppressed=%d alerting=%d", what, id,
                              kit.notchState.mode.rawValue, (vm?.hovering ?? false) ? 1 : 0,
                              NotchViewModel.hoverOpenSuppressed ? 1 : 0, NookTimersStore.shared.alertingIDs.count)
                    }
                }
                switch arg {
                case "in", "out":
                    for kit in WindowsManager.shared.displayKits.values {
                        guard let w = kit.dynamicnotchWindow, let vm = NotchViewModel.debugByWindow.object(forKey: w) else { continue }
                        vm.setPointerOver(notch: arg == "in", band: nil)
                    }
                    let t = Timer(timeInterval: 0.5, repeats: false) { _ in MainActor.assumeIsolated { log(arg + " +0.5s") } }
                    RunLoop.main.add(t, forMode: .common)
                case "stop":
                    NookTimersStore.shared.stopAllAlerts()
                    log("stop")
                default:
                    log("state")
                }
            }
        }
    }
}
#endif

#if DEBUG
extension NotchInteractionMonitor {
    /// DEBUG `notchgeom` (log, per screen: screen frame, notch size, row width, max/actual open
    /// width, open footprint, window frame, canvas; per widget: width and the height its content
    /// asks for in a `NookWidgetLayout.cellHeight` cell — more than that is clipped inside the cell).
    /// `notchgeom:aspect=<w/h>` first changes the Camera widget's aspect (as a camera reporting
    /// its format does) and logs 0.5 s later, to check that every window refits.
    fileprivate static func installDebugGeometryProbe() {
        _ = DistributedNotificationCenter.default().addObserver(forName: DebugHooks.notificationName, object: nil, queue: .main) { note in
            guard let command = note.object as? String, command == "notchgeom" || command.hasPrefix("notchgeom:") else { return }
            MainActor.assumeIsolated {
                if command.hasPrefix("notchgeom:aspect="), let v = Double(command.dropFirst("notchgeom:aspect=".count)) {
                    MirrorWidgetLayout.shared.update(CGFloat(v))
                    let t = Timer(timeInterval: 0.5, repeats: false) { _ in MainActor.assumeIsolated { logGeometry() } }
                    RunLoop.main.add(t, forMode: .common)
                } else {
                    logGeometry()
                }
            }
        }
    }

    @MainActor private static func logGeometry() {
        let settings = SettingsStore[.nookSettings]
        let row = NookWidgetLayout.rowWidth(settings.widgets, separatorSpacing: settings.separatorSpacing)
        for (id, kit) in WindowsManager.shared.displayKits {
            let g = kit.notchGeometry
            let open = NookWidgetLayout.openWidth(settings.widgets, separatorSpacing: settings.separatorSpacing, maxWidth: g.maxOpenWidth)
            let vm = kit.dynamicnotchWindow.flatMap { NotchViewModel.debugByWindow.object(forKey: $0) }
            let window = kit.dynamicnotchWindow?.frame ?? .zero
            NSLog("[notchgeom] screen %u frame=%@ notch=%@ row=%.0f maxOpen=%.0f open=%.0f footprint=%@ window=%@ canvas=%@ scrolls=%d windowFits=%d",
                  id, NSStringFromRect(kit.screen.frame), NSStringFromSize(kit.screen.hardwareNotchSize), row, g.maxOpenWidth, open,
                  NSStringFromSize(vm?.openFootprintSize ?? .zero), NSStringFromRect(window), NSStringFromSize(g.canvas),
                  row > open + 0.5 ? 1 : 0,
                  (window.width <= kit.screen.frame.width && abs(window.width - min(ceil(open) + 2 * NotchWindowGeometry.sideMargin, kit.screen.frame.width)) < 1) ? 1 : 0)
        }
        // AppKit-backed controls (text fields, popup menus) ignore SwiftUI masks: log where they are
        // and how much of them is visible (in-process snapshots may not draw them inside a ScrollView)
        for (id, kit) in WindowsManager.shared.displayKits {
            guard let root = kit.dynamicnotchWindow?.contentView else { continue }
            var stack: [NSView] = [root]
            while let v = stack.popLast() {
                stack.append(contentsOf: v.subviews)
                guard v is NSTextField || v is NSPopUpButton || v is NSButton else { continue }
                NSLog("[notchgeom] screen %u appkit %@ frame=%@ visible=%@ hidden=%d", id, String(describing: type(of: v)),
                      NSStringFromRect(v.convert(v.bounds, to: nil)), NSStringFromRect(v.visibleRect), v.isHiddenOrHasHiddenAncestor ? 1 : 0)
            }
        }
        let cellHeight = NookWidgetLayout.cellHeight
        for widget in settings.widgets {
            let w = NookWidgetLayout.width(of: widget)
            let host = NSHostingController(rootView: NookWidgetContentView(widget: widget).environment(\.colorScheme, .dark))
            // in a cell-sized proposal, and the least height the content accepts (proposal 0)
            let fit = host.sizeThatFits(in: CGSize(width: w, height: cellHeight))
            let least = host.sizeThatFits(in: CGSize(width: w, height: 0))
            let need = max(fit.height, least.height)
            NSLog("[notchgeom] widget %@ width=%.0f cells=%.2f height=%.0f minHeight=%.0f cell=%.0f%@", widget.rawValue, w,
                  NookWidgetLayout.cells(of: widget), fit.height, least.height, cellHeight, need > cellHeight + 0.5 ? " OVERFLOWS" : "")
        }
    }
}
#endif

