// DEBUG-only hooks of the Bluetooth widget (2026-10-20), registered with DebugCommandRegistry
// by DebugHooks.install (`BluetoothWidgetDebug.install()`, also still called when the widget
// appears, only re-registers).
//   btpreview:<dir>   write <dir>/bluetooth-<state>-<dark|light>.png: the live widget, and fixed
//                     sample states (list with a connect in progress and an error toast, a list
//                     with a disconnect in progress, Bluetooth off, access not determined, denied).
//                     Preview data only: nothing connects, nothing is written but the PNGs.
//   btstate[:<file>]  log the model state (authorization, power, devices with class of device);
//                     with a path, also write it to that file
//   btrefresh         re-read power state and paired devices
//   DN_BT_PREVIEW_DIR=<dir> (environment, launch): ~4 s after launch, run btpreview:<dir> and
//                     btstate:<dir>/btstate.txt without any notification (for runs where
//                     distributed notifications do not arrive). Triggered by the first
//                     NookWidgetLayout.cells(of: .bluetooth) lookup (BluetoothWidgetLayout.cells).
//                     The generic equivalent: `-DNDebugCommand btpreview:<dir>` (DebugHooks-Registry).
#if DEBUG
import SwiftUI
import AppKit
import CoreBluetooth

@MainActor
enum BluetoothWidgetDebug {
    static let rowHeight: CGFloat = WidgetSnapshotter.cellHeight

    static func install() {
        let verbs: [(String, String?, String)] = [
            ("btpreview", "btpreview:<dir>", "Bluetooth widget live + sample states (preview data only)"),
            ("btstate", "btstate[:<file>]", "log the model state (and write it to <file>)"),
            ("btrefresh", nil, "re-read power state and paired devices"),
        ]
        for (verb, usage, summary) in verbs {
            DebugCommandRegistry.register(verb, usage: usage, summary) { arg in handle(arg.isEmpty ? verb : verb + ":" + arg) }
        }
    }

    nonisolated(unsafe) private static var autoRunScheduled = false

    nonisolated static func autoRunIfRequested() {
        guard !autoRunScheduled, let dir = ProcessInfo.processInfo.environment["DN_BT_PREVIEW_DIR"], !dir.isEmpty else { return }
        autoRunScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            MainActor.assumeIsolated {
                BluetoothWidgetModel.shared.start()
                handle("btpreview:" + dir)
                handle("btstate:" + dir + "/btstate.txt")
                BluetoothWidgetModel.shared.stop()
            }
        }
    }

    static func handle(_ command: String) {
        let model = BluetoothWidgetModel.shared
        if command.hasPrefix("btpreview:") {
            WidgetSnapshotter.session(String(command.dropFirst("btpreview:".count)), tag: "[BluetoothWidget]") { render(to: $0) }
        } else if command == "btstate" || command.hasPrefix("btstate:") {
            var lines = [model.debugSummary]
            for d in model.devices {
                lines.append(String(format: "  %@ %@ kind=%@ class=%02x/%02x connected=%d", d.id, d.name ?? "(unnamed)",
                                    d.kind.rawValue, d.classMajor, d.classMinor, d.isConnected ? 1 : 0))
            }
            for line in lines { NSLog("[BluetoothWidget] %@", line) }
            if command.hasPrefix("btstate:") {   // btstate:<file> also writes the lines to a file
                try? lines.joined(separator: "\n").write(toFile: String(command.dropFirst("btstate:".count)), atomically: true, encoding: .utf8)
            }
        } else if command == "btrefresh" {
            model.refreshPower()
            model.refresh()
            NSLog("[BluetoothWidget] %@", model.debugSummary)
        }
    }

    static var sampleDevices: [BluetoothWidgetDevice] {
        [
            .init(id: "00:00:00:00:00:01", name: "AirPods Pro", kind: .airPodsPro, isConnected: true),
            .init(id: "00:00:00:00:00:02", name: "Magic Trackpad", kind: .trackpad, isConnected: true),
            .init(id: "00:00:00:00:00:03", name: "Keyboard K3", kind: .keyboard, isConnected: false),
            .init(id: "00:00:00:00:00:04", name: "WH-1000XM4", kind: .headphones, isConnected: false),
            .init(id: "00:00:00:00:00:05", name: "Living Room Speaker", kind: .speaker, isConnected: false),
            .init(id: "00:00:00:00:00:06", name: "Wireless Controller", kind: .gameController, isConnected: false),
            .init(id: "00:00:00:00:00:07", name: nil, kind: .other, isConnected: false),
        ]
    }

    static func render(to dir: URL) {
        let devices = sampleDevices
        let states: [(String, BluetoothWidgetDisplayState?)] = [
            ("live", nil),
            ("sample-list", .init(authorization: .allowedAlways, power: .on, devices: devices,
                                  inFlight: ["00:00:00:00:00:03": .connecting],
                                  toast: String(format: String(localized: "Couldn’t connect to %@"), "WH-1000XM4"),
                                  batteries: ["00:00:00:00:00:01": 84, "00:00:00:00:00:02": 15])),
            ("sample-list-notoast", .init(authorization: .allowedAlways, power: .on, devices: devices,
                                          inFlight: ["00:00:00:00:00:02": .disconnecting],
                                          batteries: ["00:00:00:00:00:01": 84])),
            ("sample-off", .init(authorization: .allowedAlways, power: .off, devices: devices)),
            ("sample-access", .init(authorization: .notDetermined, power: .on, devices: [])),
            ("sample-denied", .init(authorization: .denied, power: .on, devices: [])),
        ]
        let width = NookWidgetLayout.width(of: .bluetooth)
        for (name, state) in states {
            WidgetSnapshotter.widget("bluetooth-\(name)", in: dir, width: width, height: rowHeight) {
                BluetoothWidgetView(preview: state)
            }
        }
    }
}
#endif
