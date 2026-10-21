// DEBUG-only preview of the Color Picker widget (2026-10-20), registered with
// DebugCommandRegistry by DebugHooks.install (`ColorPickerDebug.install()`, also still called when
// the widget appears, only re-registers):
//   colorpreview:<dir>   write <dir>/colorpicker-<sample|light|empty>-<dark|light>.png (the widget
//                        offscreen at its grid width × 202 pt with an in-memory sample history —
//                        nothing is sampled, copied or saved) and colorpicker-settings-<dark|light>.png
//                        (Settings ▸ Widgets ▸ Color Picker at 520 pt). The real history is restored
//                        afterwards (in memory; the history file is not touched).
#if DEBUG
import SwiftUI
import AppKit

@MainActor
enum ColorPickerDebug {
    static func install() {
        DebugCommandRegistry.register("colorpreview", usage: "colorpreview:<dir>", "Color Picker widget sample / light / empty + settings, format log") { arg in
            WidgetSnapshotter.session(arg, tag: "[ColorPicker]") { render(to: $0) }
        }
    }

    static let sample: [PickedColor] = [
        PickedColor(red: 0.000, green: 0.478, blue: 1.000),   // #007AFF
        PickedColor(red: 1.000, green: 0.584, blue: 0.000),
        PickedColor(red: 0.204, green: 0.780, blue: 0.349),
        PickedColor(red: 1.000, green: 0.231, blue: 0.188),
        PickedColor(red: 0.686, green: 0.322, blue: 0.871),
        PickedColor(red: 1.000, green: 0.800, blue: 0.000),
        PickedColor(red: 0.353, green: 0.784, blue: 0.980),
        PickedColor(red: 0.557, green: 0.557, blue: 0.576),
        PickedColor(red: 0.110, green: 0.110, blue: 0.118),
        PickedColor(red: 0.949, green: 0.949, blue: 0.969),
        PickedColor(red: 0.635, green: 0.518, blue: 0.369),
        PickedColor(red: 1.000, green: 0.176, blue: 0.333),
    ]

    static func render(to dir: URL) {
        let store = ColorPickerHistoryStore.shared
        store.start()
        let saved = store.colors
        let wasPreview = store.isPreview
        defer {
            store.setPreviewColors(saved)
            store.isPreview = wasPreview
        }
        let light = [PickedColor(red: 1.0, green: 0.85, blue: 0.4)] + Array(sample.prefix(5))
        let width = NookWidgetLayout.cell * 4
        for (name, colors) in [("sample", sample), ("light", light), ("empty", [PickedColor]())] {
            store.setPreviewColors(colors)
            WidgetSnapshotter.widget("colorpicker-\(name)", in: dir, width: width) { ColorPickerWidgetView() }
        }
        store.setPreviewColors(sample)
        WidgetSnapshotter.settings("colorpicker-settings", in: dir, size: CGSize(width: 520, height: 520)) { ColorPickerWidgetSettingsView() }
        // log every format of the first sample colour (format check)
        for format in ColorCopyFormat.allCases {
            NSLog("[ColorPicker] %@ → %@", format.rawValue, sample[0].formatted(format))
        }
        NSLog("[ColorPicker] contrast #007AFF: white %@ black %@",
              PickedColor.ratioText(sample[0].contrastOnWhite), PickedColor.ratioText(sample[0].contrastOnBlack))
    }
}
#endif
