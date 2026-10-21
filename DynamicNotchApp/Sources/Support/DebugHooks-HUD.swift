// F5 (2026-10-20): DEBUG-only commands of the volume / brightness HUD, registered with
// DebugCommandRegistry by HUDMonitor.start() (`HUDDebugHooks.install()`).
//   hudstate                 log HUDMonitor's state (key source, permissions, events seen, volume),
//                            the IOKit / IORegistry brightness probes and one corebrightnessdiag read.
//   hudkey:<NX_KEYTYPE>      feed a media key to the HUD as if the tap had seen it (0 = sound up,
//                            1 = down, 7 = mute, 2/3 = brightness up/down, 21/22/23 = illumination).
//                            Only the HUD reacts; nothing is sent to the system.
//   hudsim:<kind>[:<level>]  show a reading directly (kind = volume | muted | brightness | keyboard,
//                            level 0…1 or "none").
//   hudpreview:<dir>         write <dir>/hud-notch-<case>.png: the closed-notch activity on a mock
//                            notch for a set of readings (no monitor state involved).
#if DEBUG
import SwiftUI
import AppKit
import os

@MainActor
enum HUDDebugHooks {
    /// Public (unredacted) log lines: `log stream --predicate 'category == "hud-debug"'`.
    nonisolated static let logger = Logger(subsystem: "com.example.dynamicnotch.DynamicNotch", category: "hud-debug")

    nonisolated static func log(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }

    /// Registers the commands (called by HUDMonitor.start(); re-registering is idempotent).
    static func install() {
        let r = DebugCommandRegistry.self
        r.register("hudstate", "log the HUD state, the IOKit / IORegistry brightness probes and one corebrightnessdiag read") { _ in
            logState()
        }
        r.register("hudkey", usage: "hudkey:<NX_KEYTYPE>", "feed a media key to the HUD only (0/1/7 volume, 2/3 brightness, 21/22/23 illumination)") { arg in
            if let type = Int32(arg) { HUDMonitor.shared.handleMediaKey(type) }
            log("[HUD] \(HUDMonitor.shared.debugDescription)")
        }
        r.register("hudsim", usage: "hudsim:<volume|muted|brightness|keyboard>[:<level|none>]", "show a HUD reading directly") { arg in
            let parts = arg.split(separator: ":", maxSplits: 1).map(String.init)
            let kindName = parts.first ?? "volume"
            let level: Double? = parts.count > 1 ? Double(parts[1]) : 0.5
            let monitor = HUDMonitor.shared
            switch kindName {
            case "brightness": monitor.show(.init(kind: .brightness, level: level, direction: .up))
            case "keyboard": monitor.show(.init(kind: .keyboardBacklight, level: level, direction: .up))
            case "muted": monitor.show(.init(kind: .volume, level: level, muted: true, direction: .toggle))
            default: monitor.show(.init(kind: .volume, level: level, direction: .up))
            }
            log("[HUD] \(monitor.debugDescription) la=\(LiveActivityCenter.shared.debugDescription)")
        }
        r.register("hudpreview", usage: "hudpreview:<dir>", "closed-notch HUD states on a mock notch + the settings pane (no monitor state)") { arg in
            if !arg.isEmpty { preview(to: URL(fileURLWithPath: arg)) }
        }
    }

    private static func logState() {
        let monitor = HUDMonitor.shared
        monitor.refreshPermissions()
        log("[HUD] \(monitor.debugDescription)")
        let io = HUDCoreBrightness.ioDisplayBrightness()
        log("[HUD] IODisplayGetFloatParameter: result=\(String(format: "0x%08x", io.result)) value=\(io.value.map { "\($0)" } ?? "nil")")
        log("[HUD] AppleARMBacklight IODisplayParameters: \(HUDCoreBrightness.armBacklightParameters().map { "\($0)" } ?? "nil")")
        DispatchQueue.global().async {
            let start = Date()
            let snapshot = HUDCoreBrightness.read()
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            log("[HUD] corebrightnessdiag (\(ms) ms): \(snapshot.map { "display=\($0.displayBrightness.map { "\($0)" } ?? "nil") keyboard=\($0.keyboardBrightness.map { "\($0)" } ?? "nil")" } ?? "nil")")
        }
    }

    private static func preview(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let cases: [(String, HUDMonitor.Reading)] = [
            ("volume-60", .init(kind: .volume, level: 0.6, direction: .up)),
            ("volume-0", .init(kind: .volume, level: 0, direction: .down)),
            ("volume-muted", .init(kind: .volume, level: 0.45, muted: true, direction: .toggle)),
            ("volume-unavailable", .init(kind: .volume, level: nil, direction: .up)),
            ("brightness-80", .init(kind: .brightness, level: 0.8, direction: .up)),
            ("brightness-10", .init(kind: .brightness, level: 0.1, direction: .down)),
            ("keyboard-50", .init(kind: .keyboardBacklight, level: 0.5, direction: .up)),
            ("keyboard-unknown", .init(kind: .keyboardBacklight, level: nil, direction: .down)),
        ]
        let notch = CGSize(width: 185, height: 32)
        let side = HUDLiveActivityView.sideWidth(notchHeight: notch.height)
        for (name, reading) in cases {
            let view = HStack(spacing: 0) {
                HUDLiveActivityView(side: .leading, preview: reading)
                    .padding(.leading, ClosedNotchActivityLayout.outerInset).padding(.trailing, 4)
                    .frame(width: side, height: notch.height, alignment: .leading)
                Color.clear.frame(width: notch.width, height: notch.height)
                HUDLiveActivityView(side: .trailing, preview: reading)
                    .padding(.trailing, ClosedNotchActivityLayout.outerInset).padding(.leading, 4)
                    .padding(.vertical, 4)
                    .frame(width: side, height: notch.height, alignment: .trailing)
            }
            .background(UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10).fill(Color.black))
            .padding(16)
            .background(Color(white: 0.55))
            .environment(\.colorScheme, .dark)
            writePNG(view, size: CGSize(width: notch.width + 2 * side + 32, height: notch.height + 32),
                     to: dir.appendingPathComponent("hud-notch-\(name).png"))
        }
        let settings = HUDSettingsView()
            .frame(width: 600, height: 640)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .dark)
        writePNG(settings, size: CGSize(width: 600, height: 640), to: dir.appendingPathComponent("hud-settings.png"))
    }

    private static func writePNG<V: View>(_ view: V, size: CGSize, to url: URL) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        host.layoutSubtreeIfNeeded()
        host.display()
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: url)
                log("[HUD] wrote \(url.path)")
            }
        }
        window.orderOut(nil)
        window.close()
    }
}
#endif
