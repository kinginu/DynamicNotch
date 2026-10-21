// DEBUG-only commands of the Batteries widget (2026-10-20), registered with
// DebugCommandRegistry by DebugHooks.install:
//   batlog              start the manager, refresh, and log every device and the per-source counts
//                       ~2 s later ("[Batteries] …")
//   batpreview:<dir>    write <dir>/batteries-<live|sample|many|empty>-<dark|light>.png (the widget
//                       offscreen at its grid width × 202 pt; `live` = the devices found, `sample` =
//                       Notification Center's example, `many` = 8 devices → two columns, `empty`)
//                       and settings-<dark|light>.png (Settings ▸ Widgets ▸ Batteries at 520 pt).
#if DEBUG
import SwiftUI
import AppKit

extension DebugHooks {
    @MainActor static func registerBatteriesCommands() {
        DebugCommandRegistry.register("batlog", "start the manager, refresh, log every device ~2.5 s later") { _ in
            let manager = BatteryDevicesManager.shared
            manager.start()
            manager.refresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { logBatteries() }
        }
        DebugCommandRegistry.register("batpreview", usage: "batpreview:<dir>", "Batteries widget live / sample / many / empty + settings") { arg in
            BatteryDevicesManager.shared.start()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                logBatteries()
                WidgetSnapshotter.session(arg, tag: "[Batteries]") { batteriesPreview(to: $0) }
            }
        }
    }

    @MainActor private static func logBatteries() {
        let m = BatteryDevicesManager.shared
        NSLog("[Batteries] sources %@ bluetoothAuthorization=%ld", m.sourceSummary.description, m.bluetoothAuthorization.rawValue)
        for d in m.devices {
            NSLog("[Batteries] %@ | %@ | %@ | %ld%% charging=%d low=%d plugged=%d source=%@",
                  d.id, d.name, d.kind.rawValue, d.percent, d.isCharging, d.isLowPower, d.isPluggedIn, d.source.rawValue)
        }
    }

    static let batterySample: [BatteryDevice] = [
        BatteryDevice(id: "mac", name: "MacBook Pro", kind: .mac, percent: 50, isCharging: false, isLowPower: false, isPluggedIn: true, source: .powerSource),
        BatteryDevice(id: "a:buds", name: "AirPods Pro", kind: .airPodsPro, percent: 77, isCharging: false, isLowPower: false, source: .systemProfiler),
        BatteryDevice(id: "a:case", name: "AirPods Pro Case", kind: .airPodsProCase, percent: 47, isCharging: true, isLowPower: false, isPluggedIn: true, source: .systemProfiler),
        BatteryDevice(id: "t", name: "Magic Trackpad", kind: .trackpad, percent: 15, isCharging: false, isLowPower: true, source: .ioRegistry),
        BatteryDevice(id: "c", name: "Cornix", kind: .keyboard, percent: 67, isCharging: false, isLowPower: false, source: .bluetoothLE),
    ]

    @MainActor private static func batteriesPreview(to dir: URL) {
        let many = batterySample + [
            BatteryDevice(id: "m", name: "Magic Mouse", kind: .mouse, percent: 92, isCharging: false, isLowPower: false, source: .ioRegistry),
            BatteryDevice(id: "k", name: "Magic Keyboard", kind: .keyboard, percent: 8, isCharging: false, isLowPower: true, source: .ioRegistry),
            BatteryDevice(id: "x", name: "AirPods Max", kind: .airPodsMax, percent: 100, isCharging: true, isLowPower: false, isPluggedIn: true, source: .systemProfiler),
        ]
        let live = SettingsStore[.batteriesWidgetSettings].visible(BatteryDevicesManager.shared.devices)
        let cases: [(String, [BatteryDevice]?)] = [("live", nil), ("sample", batterySample), ("many", many), ("empty", [])]
        for (name, devices) in cases {
            let count = devices?.count ?? live.count
            let cells = count > BatteriesWidgetLayout.rowsPerColumn ? BatteriesWidgetLayout.twoColumnCells : BatteriesWidgetLayout.oneColumnCells
            WidgetSnapshotter.widget("batteries-\(name)", in: dir, width: cells * NookWidgetLayout.cell) {
                BatteriesWidgetView(previewDevices: devices)
            }
        }
        WidgetSnapshotter.settings("settings", in: dir, size: CGSize(width: 520, height: 640)) { BatteriesWidgetSettingsView() }
    }
}
#endif
