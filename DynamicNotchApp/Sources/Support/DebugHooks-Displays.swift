// DEBUG-only commands of the Displays widget (2026-10-21), registered with
// DebugCommandRegistry by DebugHooks.install (`DisplaysWidgetDebug.install()`):
//   displayslog              read every display once and log what the service found ("[Displays] …")
//   displayspreview:<dir>    write <dir>/displays-<live|sample|one|unavailable|ddc-off|empty>-<dark|light>.png
//                            (the widget offscreen at 5 cells × 202 pt; `sample` = built-in + two
//                            fake DDC monitors with contrast / volume shown, `one` = built-in only,
//                            `unavailable` = a monitor that does not answer, `ddc-off` = DDC/CI turned off) and
//                            displays-settings-<dark|light>.png (Settings ▸ Widgets ▸ Displays).
// Read-only: the live case and the log only read (DisplayServices getter, IORegistry, DDC Get VCP /
// Capabilities); the sample cases run on fake hardware. Nothing is written except the PNGs.
#if DEBUG
import SwiftUI
import AppKit
import CoreGraphics

@MainActor
enum DisplaysWidgetDebug {
    static func install() {
        DebugCommandRegistry.register("displayslog", "read every display once and log the result") { _ in
            DisplayControlService.shared.refresh { log() }
        }
        DebugCommandRegistry.register("displayspreview", usage: "displayspreview:<dir>",
                                      "Displays widget live / sample / one / unavailable / empty + settings") { arg in
            DisplayControlService.shared.start()
            DisplayControlService.shared.refresh {
                log()
                previews { cases in
                    WidgetSnapshotter.session(arg, tag: "[Displays]") { preview(to: $0, cases: cases) }
                }
            }
        }
    }

    private static func log() {
        let service = DisplayControlService.shared
        for d in service.displays {
            let s = service.state(d.id)
            func pct(_ v: Double?) -> String { v.map { "\(Int(($0 * 100).rounded()))%" } ?? "-" }
            NSLog("[Displays] id=%u %@ builtin=%d key=%@ ddc=%@ brightness=%@%@ contrast=%@ volume=%@ input=%@ caps=%@",
                  d.id, d.name, d.isBuiltIn, d.key, String(describing: s.ddc), pct(s.brightness),
                  s.brightnessApproximate ? " (approx)" : "", pct(s.contrast), pct(s.volume),
                  s.inputSource.map { DDCInputSource.name(UInt16($0)) } ?? "-", s.capabilities?.model ?? "-")
        }
        NSLog("[Displays] built-in backend: %@, DDC available: %d",
              service.hardware.builtInBackendName, service.hardware.supportsDDC)
    }

    typealias Case = (name: String, service: DisplayControlService?, settings: DisplaysWidgetSettings?)

    /// Builds the fake-hardware services, refreshes them, then hands the cases over.
    private static func previews(_ done: @escaping @MainActor ([Case]) -> Void) {
        typealias P = PreviewDisplayHardware
        var all = DisplaysWidgetSettings()
        all.showContrast = true
        var off = DisplaysWidgetSettings()
        off.ddcEnabled = false
        let made: [(String, PreviewDisplayHardware, DisplaysWidgetSettings)] = [
            ("sample", PreviewDisplayHardware(displays: [P.builtIn, P.dell1, P.lg], silent: []), all),
            ("one", PreviewDisplayHardware(displays: [P.builtIn], silent: []), .default),
            ("unavailable", PreviewDisplayHardware(displays: [P.builtIn, P.dell1, P.lg], silent: [P.lg.id]), .default),
            ("ddc-off", PreviewDisplayHardware(displays: [P.builtIn, P.dell1], silent: []), off),
            ("empty", PreviewDisplayHardware(displays: [], silent: []), .default),
        ]
        var cases: [Case] = [("live", nil, nil)]
        var pending = made.count
        for (name, hw, settings) in made {
            let service = DisplayControlService(hardware: hw, settings: { settings })
            service.isManual = true
            cases.append((name, service, settings))
            service.refresh {
                pending -= 1
                if pending == 0 { done(cases) }
            }
        }
    }

    private static func preview(to dir: URL, cases: [Case]) {
        let width = DisplaysWidgetLayout.cells * NookWidgetLayout.cell
        for c in cases {
            WidgetSnapshotter.widget("displays-\(c.name)", in: dir, width: width) {
                DisplaysWidgetView(previewService: c.service, previewSettings: c.settings)
            }
        }
        WidgetSnapshotter.settings("displays-settings", in: dir, size: CGSize(width: 520, height: 640)) {
            DisplaysWidgetSettingsView()
        }
    }
}

/// Fake displays for the previews: a built-in panel and DDC monitors backed by FakeDDCMonitor.
final class PreviewDisplayHardware: DisplayHardware, @unchecked Sendable {
    static let builtIn = DisplayInfo(id: 1, name: "Built-in Retina Display", isBuiltIn: true, isMain: false,
                                     vendor: 1552, model: 41038, serial: 1)
    static let dell1 = DisplayInfo(id: 3, name: "DELL P3225QE (1)", isBuiltIn: false, isMain: true,
                                   vendor: 4268, model: 17277, serial: 1093753164)
    static let lg = DisplayInfo(id: 4, name: "LG UltraFine", isBuiltIn: false, isMain: false,
                                vendor: 7789, model: 23305, serial: 77)

    private let list: [DisplayInfo]
    private let monitors: [CGDirectDisplayID: FakeDDCMonitor]

    /// `silent`: monitors without a DDC/CI connection.
    init(displays: [DisplayInfo], silent: Set<CGDirectDisplayID>) {
        list = displays
        var m: [CGDirectDisplayID: FakeDDCMonitor] = [:]
        for d in displays where !d.isBuiltIn && !silent.contains(d.id) {
            if d.id == Self.lg.id {
                m[d.id] = FakeDDCMonitor(values: [
                    VCPCode.brightness.rawValue: .init(current: 35, maximum: 100),
                    VCPCode.contrast.rawValue: .init(current: 70, maximum: 100),
                    VCPCode.audioVolume.rawValue: .init(current: 20, maximum: 100),
                    VCPCode.inputSource.rawValue: .init(current: 0x0F, maximum: 0x12),
                ], capabilities: "(prot(monitor)type(lcd)model(ULTRAFINE)vcp(10 12 60(0F 11) 62)mccs_ver(2.2))")
            } else {
                m[d.id] = FakeDDCMonitor(values: [
                    VCPCode.brightness.rawValue: .init(current: 74, maximum: 100),
                    VCPCode.contrast.rawValue: .init(current: 75, maximum: 100),
                    VCPCode.inputSource.rawValue: .init(current: 0x1B1B, maximum: 0x0E),
                ], capabilities: "(prot(monitor)type(lcd)model(P3225QE)vcp(10 12 60( 1B 0F 11))mccs_ver(2.1))")
            }
        }
        monitors = m
    }

    @MainActor func displays() -> [DisplayInfo] { list }
    func builtInBrightness(_ display: CGDirectDisplayID) -> Double? { 0.43 }
    func canSetBuiltInBrightness(_ display: CGDirectDisplayID) -> Bool { true }
    func setBuiltInBrightness(_ value: Double, display: CGDirectDisplayID) -> Bool { true }
    func ddcChannels(for displays: [DisplayInfo]) -> [CGDirectDisplayID: DDCChannel] {
        monitors.mapValues { DDCChannel(transport: $0, timing: .immediate) }
    }
    var builtInBackendName: String { "Preview" }
    var builtInBrightnessIsApproximate: Bool { false }
    var supportsDDC: Bool { true }
}
#endif
