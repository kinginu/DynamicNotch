import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
import UniformTypeIdentifiers

// Pinned applications (SettingsStore[.quickAppsPaths], edited in Settings ▸ Nook ▸ Widgets ▸ Quick
//   Apps or with the + button) are listed; click launches / activates the app.
// rows-and-columns layout (2026-10-20, user feedback: names under the icons were
//   truncated — "Bitwar…"). Each app is a ROW: its 30 pt icon with the full name to the right in one
//   line (names hidden when "Show app names" is off → icon-only columns). Up to 5 rows per column;
//   further apps start a new column and the widget grows by it
//   (`QuickAppsWidgetLayout.shared.preferredCells()` for `NookWidgetLayout.cells(of: .quickApps)`).
//   A small "+" row at the end of the last column adds apps. Shared machinery: `NookRowColumns*`
//   in WidgetUI/WidgetRowColumns.swift.
struct QuickAppsWidgetView: View {
    @StoredSetting(.quickAppsPaths) private var paths
    @StoredSetting(.quickAppsWidgetSettings) private var settings

    /// DEBUG snapshots: shown instead of the stored apps / setting.
    var previewApps: [URL]? = nil
    var previewShowNames: Bool? = nil

    private var apps: [URL] { previewApps ?? QuickAppsWidgetLayout.existingApps(paths) }
    private var showNames: Bool { previewShowNames ?? settings.showAppNames }

    var body: some View {
        Group {
            if apps.isEmpty {
                NookWidgetEmptyState(systemImage: "square.grid.3x3",
                                     title: String(localized: "No apps"),
                                     actionTitle: String(localized: "Add Apps…"),
                                     action: { QuickAppsPicker.addApps() })
                    .padding(NookWidgetMetrics.padding)
            } else {
                NookRowColumnsView(
                    items: apps,
                    plan: QuickAppsWidgetLayout.plan(for: apps, showNames: showNames),
                    addTitle: QuickAppsWidgetLayout.addTitle,
                    addHelp: Text("Add Apps…"),
                    addAction: { QuickAppsPicker.addApps() }
                ) { url, showsText in
                    QuickAppButton(url: url, showName: showsText)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .nookWidgetGalleryHook()
        #if DEBUG
        .onAppear { NookRowWidgetsDebug.install() }
        #endif
    }
}

/// Column plan of the Quick Apps widget for the grid (see `ShortcutsWidgetLayout`):
///   `NookWidgetLayout.cells(of: .quickApps)` reads `QuickAppsWidgetLayout.shared.preferredCells()`,
///   which tracks the stored app list and the "Show app names" setting.
@Observable
final class QuickAppsWidgetLayout {
    static let shared = QuickAppsWidgetLayout()

    /// Visible label of the "+" row.
    static var addTitle: String { String(localized: "Add Apps…") }

    /// Grid cells of the empty state (the former fixed 3 × 50 pt).
    static let emptyCells: CGFloat = 3

    private(set) var apps: [URL]
    private(set) var showNames: Bool
    @ObservationIgnored private var observer: NSObjectProtocol?

    private init() {
        apps = Self.existingApps(SettingsStore[.quickAppsPaths])
        showNames = SettingsStore[.quickAppsWidgetSettings].showAppNames
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let apps = Self.existingApps(SettingsStore[.quickAppsPaths])
            let showNames = SettingsStore[.quickAppsWidgetSettings].showAppNames
            if apps != self.apps { self.apps = apps }
            if showNames != self.showNames { self.showNames = showNames }
        }
    }

    /// Stored paths whose app still exists, in display order.
    static func existingApps(_ paths: [String]) -> [URL] {
        paths.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func displayName(of url: URL) -> String {
        FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    static func plan(for apps: [URL], showNames: Bool) -> NookRowColumnsPlan {
        NookRowColumnsPlan(names: apps.map(displayName(of:)), showNames: showNames, addTitle: addTitle)
    }

    /// Widget width in 50 pt grid cells (fractional). Reading it in a view body tracks the apps.
    func preferredCells() -> CGFloat {
        apps.isEmpty ? Self.emptyCells : Self.plan(for: apps, showNames: showNames).cells
    }
}

private struct QuickAppButton: View {
    let url: URL
    var showName: Bool
    @State private var hovering = false

    private var name: String { QuickAppsWidgetLayout.displayName(of: url) }

    var body: some View {
        Button {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } label: {
            NookIconRow(hovering: hovering, showsText: showName) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: NookRowColumnsMetrics.appIconDrawSize, height: NookRowColumnsMetrics.appIconDrawSize)
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
            } title: {
                Text(verbatim: name)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(ShrinkOnClick(minSize: 0.96))
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .help(name)
        .accessibilityLabel(Text(verbatim: name))
        .contextMenu {
            Button("Remove from Quick Apps") {
                SettingsStore[.quickAppsPaths].removeAll { $0 == url.path }
            }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
    }
}

/// Adds applications to the Quick Apps list (open panel).
enum QuickAppsPicker {
    @MainActor static func addApps() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Add Apps…")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate(ignoringOtherApps: true)
        panel.level = .modalPanel
        if panel.runModal() == .OK {
            add(panel.urls)
        }
    }

    static func add(_ urls: [URL]) {
        var list = SettingsStore[.quickAppsPaths]
        for url in urls where url.pathExtension == "app" && !list.contains(url.path) {
            list.append(url.path)
        }
        SettingsStore[.quickAppsPaths] = list
    }
}
