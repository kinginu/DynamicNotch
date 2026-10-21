// DEBUG-only DebugHooks commands of the Tray and drops (registered with DebugCommandRegistry by
// DebugHooks.install).
//   trayadd:<path>[|<path>…] add file(s) through the drop code path (NotchDropController.handleDrop → Tray)
//   traytext:<text>       drop a text clipping (materialized into a .txt tray item)
//   traydrag[:<target>]   simulate a drag over the notch (mode .dragging; pointer over tray|airdrop)
//   trayenddrag           end a simulated drag without dropping (→ closed)
//   trayselect:<index>    select tray item <index> (files order)
//   trayremove:<index>    remove tray item <index>
//   trayclear             remove everything
//   traystate             print the tray contents / mode / live activities to stdout
#if DEBUG
import AppKit
import SwiftUI

extension DebugHooks {
    @MainActor static func registerCommandsC() {
        let r = DebugCommandRegistry.self
        for verb in ["trayadd", "traytext"] {
            r.register(verb, usage: verb == "trayadd" ? "trayadd:<path>[|<path>…]" : "traytext:<text>",
                       verb == "trayadd" ? "add file(s) through the drop code path" : "drop a text clipping (→ .txt tray item)") { arg in
                let pasteboard = NSPasteboard(name: NSPasteboard.Name("dn.debug.drop.\(UUID().uuidString)"))
                pasteboard.clearContents()
                if verb == "trayadd" {
                    pasteboard.writeObjects(arg.split(separator: "|").map { URL(fileURLWithPath: String($0)) as NSURL })
                } else {
                    pasteboard.setString(arg, forType: .string)
                }
                guard let controller = NotchDropController.debugInstance else {
                    print("[DebugHooks-C] no NotchDropController"); return
                }
                controller.handleDrop(pasteboard: pasteboard, target: .tray)
            }
        }
        r.register("traydrag", usage: "traydrag[:tray|airdrop]", "simulate a drag over the notch") { arg in
            NotchDropController.debugInstance?.debugSimulateDrag(target: NotchDropTarget(rawValue: arg) ?? .tray)
        }
        r.register("trayenddrag", "end a simulated drag without dropping") { _ in
            NotchDropController.debugInstance?.finish(close: true)
        }
        r.register("trayselect", usage: "trayselect:<index>", "select tray item <index>") { arg in
            let tray = Tray.shared
            if let i = Int(arg), tray.files.indices.contains(i) { tray.selectFile(tray.files[i]) }
        }
        r.register("trayremove", usage: "trayremove:<index>", "remove tray item <index>") { arg in
            let tray = Tray.shared
            if let i = Int(arg), tray.files.indices.contains(i) { tray.removeFile(tray.files[i]) }
        }
        r.register("trayclear", "remove everything from the tray") { _ in
            Tray.shared.removeAll()
        }
        r.register("traystate", "print the tray contents / mode / live activities to stdout") { _ in
            let tray = Tray.shared
            print("[DebugHooks-C] mode=\(DynamicNotchState.shared.mode.rawValue) files=\(tray.files.map(\.url.path)) "
                  + "items=\(tray.trayItems.count) selected=\(tray.selectedFiles.count) "
                  + "targets=\(NotchDropController.debugInstance?.viewModel.targetsCoords ?? [:]) coords=\(String(describing: NotchDropController.debugInstance?.viewModel.droppingCoords)) hovered=\(String(describing: NotchDropController.debugInstance?.viewModel.hoveredDropTargetID)) "
                  + "liveActivities=\(ActiveLiveActivitiesManager.shared.activeLiveActivities.map(\.id))")
            fflush(stdout)
        }
    }
}

extension NotchDropController {
    /// Pretends a drag hovers `target`: opens the notch in .dragging and puts droppingCoords at
    /// the target's centre once the targets have published their frames.
    func debugSimulateDrag(target: NotchDropTarget) {
        debugBeginDragging()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, let frame = self.viewModel.targetsCoords[target.rawValue] else { return }
            self.viewModel.droppingCoords = CGPoint(x: frame.midX, y: frame.midY)
        }
    }
}
#endif
