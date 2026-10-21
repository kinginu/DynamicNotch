// DEBUG-only commands of the Capture widget (2026-10-20), registered with
// DebugCommandRegistry by DebugHooks.install:
//   capturepreview:<dir>   write <dir>/capture-<idle|recording|countdown|stopping|capturing|message>-<dark|light>.png
//                          (the widget offscreen at 200 × 202 pt; the phases are set without running
//                          screencapture and reset to idle afterwards), capture-closed-indicator.png
//                          (the closed-notch recording indicator on a menu-bar strip) and
//                          settings-<dark|light>.png (Settings ▸ Widgets ▸ Capture at 520 pt).
// Nothing is captured, written to the Desktop / clipboard / tray, or stored.
#if DEBUG
import SwiftUI
import AppKit

extension DebugHooks {
    @MainActor static func registerCaptureCommands() {
        DebugCommandRegistry.register("capturepreview", usage: "capturepreview:<dir>",
                                      "Capture widget in every phase, closed-notch indicator, settings (nothing captured)") { arg in
            WidgetSnapshotter.session(arg, tag: "[Capture]") { capturePreview(to: $0) }
        }
    }

    @MainActor private static func capturePreview(to dir: URL) {
        let manager = CaptureManager.shared
        guard !manager.isBusy else { NSLog("[Capture] busy, preview skipped"); return }
        let width = NookWidgetLayout.width(of: .capture)
        let phases: [(String, CaptureManager.Phase, String?)] = [
            ("idle", .idle, nil),
            ("message", .idle, String(localized: "Saved to Desktop")),
            ("countdown", .countdown(kind: .area, fireDate: Date().addingTimeInterval(3.2)), nil),
            ("capturing", .capturing(.window), nil),
            ("recording", .recording(started: Date().addingTimeInterval(-74)), nil),
            ("stopping", .stopping, nil),
        ]
        for (name, phase, message) in phases {
            manager.debugSetPhase(phase, message: message)
            WidgetSnapshotter.widget("capture-\(name)", in: dir, width: width) { CaptureWidgetView() }
            if name == "recording" {
                let notch = CGSize(width: 185, height: 32)
                let side = CaptureClosedNotchIndicator.extraSideWidth(activity: nil, notchHeight: notch.height)
                let strip = ZStack {
                    Color(white: 0.75)
                    UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10)
                        .fill(Color.black)
                        .frame(width: notch.width + 2 * side, height: notch.height)
                    CaptureClosedNotchIndicator(notchSize: notch)
                }
                .frame(width: notch.width + 2 * side + 80, height: notch.height)
                .environment(\.colorScheme, .dark)
                WidgetSnapshotter.write(strip, size: CGSize(width: notch.width + 2 * side + 80, height: notch.height), dark: true,
                                        to: dir.appendingPathComponent("capture-closed-indicator.png"))
            }
        }
        manager.debugSetPhase(.idle)
        WidgetSnapshotter.settings("settings", in: dir, size: CGSize(width: 520, height: 900)) { CaptureWidgetSettingsView() }
    }
}
#endif
