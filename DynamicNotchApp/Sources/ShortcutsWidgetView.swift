import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
//
//   VStack with _ConditionalContent (empty vs populated branches)
//   Branch 1 (no shortcuts): Image + Text("No Shortcuts") > Button("Add Shortcut")
//   Branch 2: Group > ShortcutsRowView
//
// The chosen shortcuts (Settings ▸ Nook ▸ Widgets ▸ Shortcuts, stored in
//   SettingsStore[.shortcutsWidgetSelection]) are listed as buttons; clicking one runs it with
//   `/usr/bin/shortcuts run <name>` and shows a spinner / checkmark / error mark.

// rows-and-columns layout (2026-10-20, user feedback: names under the icons were
//   truncated — "Start 1…"). Each shortcut is a ROW: a 30 pt colour tile (colour derived from the
//   name, Shortcuts' palette; the SF Symbol turns into a spinner / checkmark / warning while it
//   runs) with the full name to its right in one line. Rows stack into a column of up to 5
//   (36 pt rows in the 202 pt cell); further rows start a new column to the right and the widget
//   grows by that column (`ShortcutsWidgetLayout.shared.preferredCells()`, read by
//   `NookWidgetLayout.cells(of: .shortcuts)`). Column widths follow the longest name in the column
//   (134…220 pt), so names are only truncated when they are really long (tooltip has the full
//   name). A small "+" row at the end of the last column opens the widget settings.
//   The row/column machinery (`NookRowColumns*`) is shared with the Quick Apps widget.
struct ShortcutsWidgetView: View {
    @StoredSetting(.shortcutsWidgetSelection) private var selection

    /// DEBUG snapshots: shown instead of the stored selection, with fixed run states.
    var previewNames: [String]? = nil
    var previewStates: [String: NookShortcutRunState] = [:]

    private var names: [String] { previewNames ?? selection }

    var body: some View {
        Group {
            if names.isEmpty {
                NookWidgetEmptyState(
                    systemImage: "square.stack.3d.up",
                    title: String(localized: "No Shortcuts"),
                    actionTitle: String(localized: "Add Shortcut"),
                    action: { NookSettingsNavigation.showWidgetSettings(.shortcuts) }
                )
                .padding(NookWidgetMetrics.padding)
            } else {
                NookRowColumnsView(
                    items: names,
                    plan: ShortcutsWidgetLayout.plan(for: names),
                    addTitle: ShortcutsWidgetLayout.addTitle,
                    addHelp: Text("Choose Shortcuts…"),
                    addAction: { NookSettingsNavigation.showWidgetSettings(.shortcuts) }
                ) { name, showsText in
                    NookShortcutButton(name: name, showsText: showsText,
                                       initialState: previewStates[name] ?? .idle)
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

// MARK: - Intrinsic width

/// Column plan of the Shortcuts widget for the grid: `NookWidgetLayout.cells(of: .shortcuts)` reads
///   `ShortcutsWidgetLayout.shared.preferredCells()` (like `MirrorWidgetLayout`), which tracks the
///   stored selection, so the widget grows by one column when a sixth / eleventh … shortcut is added.
@Observable
final class ShortcutsWidgetLayout {
    static let shared = ShortcutsWidgetLayout()

    /// Visible label of the "+" row.
    static var addTitle: String { String(localized: "Add Shortcut") }

    /// Grid cells of the empty state (the former fixed 3 × 50 pt).
    static let emptyCells: CGFloat = 3

    private(set) var names: [String]
    @ObservationIgnored private var observer: NSObjectProtocol?

    private init() {
        names = Self.storedNames()
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let stored = Self.storedNames()
            if stored != self.names { self.names = stored }
        }
    }

    private static func storedNames() -> [String] { SettingsStore[.shortcutsWidgetSelection] }

    static func plan(for names: [String]) -> NookRowColumnsPlan {
        NookRowColumnsPlan(names: names, showNames: true, addTitle: addTitle)
    }

    /// Widget width in 50 pt grid cells (fractional, like the Mirror widget). Reading it in a view
    ///   body tracks the selection.
    func preferredCells() -> CGFloat {
        names.isEmpty ? Self.emptyCells : Self.plan(for: names).cells
    }
}

// MARK: - Shortcut row

enum NookShortcutRunState { case idle, running, succeeded, failed }

/// One shortcut row: runs it on click and shows its state in the tile.
private struct NookShortcutButton: View {
    let name: String
    var showsText: Bool = true

    @State private var state: NookShortcutRunState
    @State private var hovering = false

    init(name: String, showsText: Bool = true, initialState: NookShortcutRunState = .idle) {
        self.name = name
        self.showsText = showsText
        _state = State(initialValue: initialState)
    }

    /// Shortcuts' tile colours; picked from the name so a shortcut keeps its colour.
    private static let palette: [Color] = [.red, .orange, .yellow, .green, .mint, .teal, .cyan, .blue, .indigo, .purple, .pink]

    private var tint: Color {
        let hash = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
        return Self.palette[hash % Self.palette.count]
    }

    var body: some View {
        Button {
            guard state != .running else { return }
            state = .running
            ShortcutsManager.run(name) { status in
                state = status == 0 ? .succeeded : .failed
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if state != .running { state = .idle }
                }
            }
        } label: {
            NookIconRow(hovering: hovering, showsText: showsText) {
                ZStack {
                    RoundedRectangle(cornerRadius: NookRowColumnsMetrics.iconCornerRadius, style: .continuous)
                        .fill(tint.gradient)
                    Group {
                        switch state {
                        case .idle:
                            Image(systemName: "square.stack.3d.up.fill")
                        case .running:
                            ProgressView().controlSize(.small).tint(.white)
                        case .succeeded:
                            Image(systemName: "checkmark")
                        case .failed:
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                    }
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                }
            } title: {
                Text(verbatim: name)
                    .foregroundStyle(state == .failed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            }
        }
        .buttonStyle(ShrinkOnClick(minSize: 0.96))
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .help(name)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityHint(Text("Runs the shortcut"))
    }
}

// MARK: - DEBUG snapshots

#if DEBUG
/// DEBUG: `rowwidgets:<dir>` (DebugHooks notification; the listener is installed when a Shortcuts or
///   Quick Apps widget first appears, e.g. after `widgetgallery:`) writes the Shortcuts and Quick
///   Apps widgets with sample data at 3 / 5 / 8 / 12 items, each at its preferred width
///   (`NookRowColumnsPlan.widgetWidth`), dark and light, plus `*-at150` renders at the former fixed
///   3-cell width (horizontal scroll fallback). Shortcuts are not run; Quick Apps uses apps from
///   /System/Applications; nothing is stored.
@MainActor
enum NookRowWidgetsDebug {
    private static var observer: NSObjectProtocol?

    static func install() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: DebugHooks.notificationName, object: nil, queue: .main
        ) { note in
            guard let command = note.object as? String, command.hasPrefix("rowwidgets:") else { return }
            let dir = String(command.dropFirst("rowwidgets:".count))
            MainActor.assumeIsolated { render(to: URL(fileURLWithPath: dir)) }
        }
    }

    static let sampleShortcuts = [
        "Start 1-on-1 Meeting Notes", "Bitwarden Unlock", "Focus: Deep Work", "Log Water",
        "Resize Images for Web", "Send ETA to Home", "Toggle Dark Mode", "Morning Routine",
        "Make GIF", "Text Last Image", "Translate Clipboard", "Shazam It",
    ]

    static func sampleApps() -> [URL] {
        let names = ["Calendar", "Notes", "Music", "Photos", "Reminders", "Maps", "System Settings",
                     "Calculator", "Weather", "TextEdit", "App Store", "Preview"]
        return names.map { URL(fileURLWithPath: "/System/Applications/\($0).app") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func render(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let previousGlass = NookGlass.forceFallback
        NookGlass.forceFallback = true
        defer { NookGlass.forceFallback = previousGlass }
        let states: [String: NookShortcutRunState] = [
            "Bitwarden Unlock": .running, "Focus: Deep Work": .succeeded, "Log Water": .failed,
        ]
        let apps = sampleApps()
        for count in [3, 5, 8, 12] {
            let names = Array(sampleShortcuts.prefix(count))
            let sPlan = ShortcutsWidgetLayout.plan(for: names)
            let appSlice = Array(apps.prefix(count))
            let aPlan = QuickAppsWidgetLayout.plan(for: appSlice, showNames: true)
            NSLog("[NookRowWidgetsDebug] %d items: shortcuts %.0f pt = %.2f cells (%d columns), quick apps %.0f pt = %.2f cells",
                  count, sPlan.widgetWidth, sPlan.cells, sPlan.columns.count, aPlan.widgetWidth, aPlan.cells)
            for dark in [true, false] {
                let suffix = dark ? "dark" : "light"
                write(ShortcutsWidgetView(previewNames: names, previewStates: states), width: sPlan.widgetWidth, dark: dark,
                      to: dir.appendingPathComponent("shortcuts-\(count)-\(suffix).png"))
                write(QuickAppsWidgetView(previewApps: appSlice), width: aPlan.widgetWidth, dark: dark,
                      to: dir.appendingPathComponent("quickApps-\(count)-\(suffix).png"))
            }
        }
        let eight = Array(sampleShortcuts.prefix(8))
        write(ShortcutsWidgetView(previewNames: eight, previewStates: states), width: 150, dark: true,
              to: dir.appendingPathComponent("shortcuts-8-at150-dark.png"))
        let noNames = Array(apps.prefix(8))
        let plan = QuickAppsWidgetLayout.plan(for: noNames, showNames: false)
        write(QuickAppsWidgetView(previewApps: noNames, previewShowNames: false), width: plan.widgetWidth, dark: true,
              to: dir.appendingPathComponent("quickApps-8-nonames-dark.png"))
    }

    private static func write<V: View>(_ view: V, width: CGFloat, dark: Bool, to url: URL) {
        let height = NookRowColumnsMetrics.cellHeight
        let content = view
            .frame(width: width, height: height)
            .clipped()
            .padding(12)
            .background(dark ? Color.black : Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, dark ? .dark : .light)
        NookWidgetSnapshot.writePNG(content, dark: dark, size: CGSize(width: width + 24, height: height + 24),
                                    to: url, tag: "[NookRowWidgetsDebug]", settle: 0.4)
    }
}
#endif
