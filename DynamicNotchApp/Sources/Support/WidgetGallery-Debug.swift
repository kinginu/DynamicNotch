// DEBUG-only offscreen gallery of the Nook widgets (widget restyle pass, 2026-10-20).
//
// Command (same distributed notification as DebugHooks — `DebugHooks.notificationName`, i.e.
// "com.example.dynamicnotch.debug[.<DN_DEBUG_CHANNEL>]"):
//   widgetgallery:<dir>   write <dir>/widget-<name>-<size>-<dark|light>.png for every widget at its
//                         grid width (NookWidgetLayout) × the Nook row height (202 pt), Fan Control
//                         at 2x1 (100 pt) and double-wide (250 pt), Temperature at 5x1 (250 pt,
//                         widget-temperature-5x1-*), plus row-demo-dark.png (the
//                         demo's order: Media, Mirror, Calendar, Notes, Timer, Reminders) and
//                         tray-<dark|light>.png (the Tray tab content at 560 pt).
//                         Dark = black background (the notch); light = window background, to
//                         check that nothing breaks in light mode. Liquid Glass is not captured by
//                         cacheDisplay, so the gallery renders the material fallback (NookGlass).
// Registered with DebugCommandRegistry by DebugHooks.install (`nookWidgetGalleryHook()` →
// `WidgetGalleryDebug.install()` still runs when a widget appears; it only re-registers). Rendering
// goes through WidgetSnapshotter (`cacheDisplay`: materials / Liquid Glass render flat; accepts
// `<dir>?appearance=…&glass=…`).
// Nothing is applied or written except the PNGs; widgets read live data (media, calendar,
// SwiftData of the running bundle id, timers).
import SwiftUI
import AppKit
#if canImport(FanControlKit)
import FanControlKit
#endif

extension View {
    /// DEBUG: (re-)registers the widget gallery command when a widget first appears. No-op in release.
    func nookWidgetGalleryHook() -> some View {
        #if DEBUG
        return onAppear { WidgetGalleryDebug.install() }
        #else
        return self
        #endif
    }
}

#if DEBUG
@MainActor
enum WidgetGalleryDebug {
    /// Height of a widget cell in the open Nook (250 − top bar ≈ 32 − row padding 4 + 12).
    static let rowHeight: CGFloat = WidgetSnapshotter.cellHeight

    static func install() {
        DebugCommandRegistry.register("widgetgallery", usage: "widgetgallery:<dir>",
                                      "every Nook widget at its grid width, Fan Control, Temperature, Tray, the demo row") { arg in
            WidgetSnapshotter.session(arg, tag: "[WidgetGallery]") { render(to: $0) }
        }
    }

    static func render(to dir: URL) {
        // glass is not captured by cacheDisplay: the session renders the material fallback (macOS 14/15 look)
        let appearances = WidgetSnapshotter.appearances()
        let widgets: [NookWidget] = [.media, .mirror, .calendar, .notes, .timer, .reminders, .clipboard, .shortcuts, .quickApps]
        for widget in widgets {
            let width = NookWidgetLayout.width(of: widget)
            let cells = NookWidgetLayout.cells(of: widget)
            let size = String(format: cells.rounded() == cells ? "%.0fx1" : "%.1fx1", cells)
            for dark in appearances {
                write(cell(NookWidgetContentView(widget: widget), width: width, dark: dark), dark: dark,
                      size: CGSize(width: width + 24, height: rowHeight + 24),
                      to: dir.appendingPathComponent("widget-\(widget.rawValue)-\(size)-\(dark ? "dark" : "light").png"))
            }
        }
        #if canImport(FanControlKit)
        for (choice, name) in [(FanControlWidgetSettings.GridSizeChoice.medium, "2x1"), (.doubleWide, "5x1")] {
            for dark in appearances {
                write(cell(FanControlWidgetView(previewGridSize: choice), width: choice.widthInPoints, dark: dark), dark: dark,
                      size: CGSize(width: choice.widthInPoints + 24, height: rowHeight + 24),
                      to: dir.appendingPathComponent("widget-fanControl-\(name)-\(dark ? "dark" : "light").png"))
            }
        }
        // Temperature widget (2026-10-20): live history, 5 cells.
        for dark in appearances {
            let width = NookWidgetLayout.width(of: .temperature)
            write(cell(FanControlTemperatureWidgetView(isPreview: true), width: width, dark: dark), dark: dark,
                  size: CGSize(width: width + 24, height: rowHeight + 24),
                  to: dir.appendingPathComponent("widget-temperature-5x1-\(dark ? "dark" : "light").png"))
        }
        #endif
        // The Tray tab content (file tiles or the empty state).
        for dark in appearances {
            let tray = Tray.shared
            let content = Group {
                if tray.files.isEmpty { TrayEmptyView() } else { TrayFilesScrollView(tray: tray) }
            }
            write(cell(content, width: 560, dark: dark), dark: dark,
                  size: CGSize(width: 584, height: rowHeight + 24),
                  to: dir.appendingPathComponent("tray-\(dark ? "dark" : "light").png"))
        }
        // The demo's row, separated like NookWidgetGrid.
        let demo: [NookWidget] = [.media, .mirror, .calendar, .notes, .timer, .reminders]
        let row = HStack(spacing: 0) {
            ForEach(Array(demo.enumerated()), id: \.element) { index, widget in
                if index > 0 {
                    Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1).padding(.vertical, 18).padding(.horizontal, 4)
                }
                NookWidgetContentView(widget: widget)
                    .frame(width: NookWidgetLayout.width(of: widget), height: rowHeight)
                    .clipped()
            }
        }
        .padding(12)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
        let rowWidth = demo.map(NookWidgetLayout.width(of:)).reduce(0, +) + CGFloat(demo.count - 1) * 9 + 24
        if appearances.contains(true) {
            write(row, dark: true, size: CGSize(width: rowWidth, height: rowHeight + 24), to: dir.appendingPathComponent("row-demo-dark.png"))
        }
    }

    private static func cell<V: View>(_ view: V, width: CGFloat, dark: Bool) -> some View {
        WidgetSnapshotter.cell(view, width: width, height: rowHeight, dark: dark)
    }

    /// With the SwiftData container (widgets with @Query) and time for @Query / async thumbnails.
    private static func write<V: View>(_ view: V, dark: Bool, size: CGSize, to url: URL) {
        WidgetSnapshotter.write(view.nookModelContainer(), size: size, dark: dark, to: url, settle: 0.6)
    }
}
#endif
