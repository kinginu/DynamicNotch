// Nook widget row: NookWidget → View dispatch.
//
// Turns the enabled `NookSettings.widgets` into widget views (fan-control-integration.md (b)) and
// lays them out in one row:
//   - widths are multiples of the 50 pt grid cell (`NookSettings.widgetsWidthInPoints`
//     multiplies grid cells by 50); the per-widget cell counts below are chosen so each widget's
//     content fits (`gridSizeType` is not used for the width);
//   - widgets are separated by a hairline with `NookSettings.separatorSpacing` extra space on
//     both sides;
//   - the row is `rowHeight` (218 pt) tall below the top bar, whatever the notch height (the open
//     notch is notch height + 218, at least 250 — NotchView.expectedOpenFootprint);
//   - the open notch is exactly as wide as this row (`openWidth`: at least `minOpenWidth` for the
//     top bar, at most 80 % of the screen — NotchWindowGeometry.maxOpenWidth); a wider row scrolls
//     horizontally inside the notch (`\.nookRowAvailableWidth`), with edge fades on the sides
//     that have more content.
// F9 (2026-10-20): widget pages and drag-to-reorder. The widgets can be split into pages
//   (`NookSettings.pages`, NookWidgetPagesModel.swift): with several, the pages sit side by side
//   and slide (two-finger swipe, ← / →, page dots below the row), and the open notch takes the
//   current page's width. Review fix (2026-10-21): all cells are placed by hand in one container
//   keyed by widget (a widget keeps its view across pages, and one page is a strip of one), and
//   only the pages on screen are mounted (`NookWidgetPager.livePages`). Press and hold a widget to lift it, drag to
//   reorder (live reflow), hold at the notch's edge to carry it to the neighbouring page, release to
//   drop (saved to the settings). Event handling and state: NookWidgetPager.swift.
import SwiftUI

enum NookWidgetLayout {
    /// Original grid cell width (NookSettings.widgetsWidthInPoints: cells × 50).
    static let cell: CGFloat = 50
    /// Base gap between two widgets (plus `separatorSpacing` on each side of the separator).
    static let spacing: CGFloat = 8
    static let horizontalPadding: CGFloat = 12
    static let topPadding: CGFloat = 4
    static let bottomPadding: CGFloat = 12
    /// Narrowest open notch (room for the top bar: Nook/Tray tabs + settings button).
    static let minOpenWidth: CGFloat = 320
    /// Height of the widget row below the top bar (the widgets are laid out for it).
    static let rowHeight: CGFloat = 218
    /// Height of one widget cell (row minus its top/bottom padding = 202 pt). Every cell is exactly
    /// this tall and clipped to it, so a widget whose content is taller cannot stretch the row (the
    /// HStack takes its tallest child's height) and push every widget's bottom out of the panel.
    static var cellHeight: CGFloat { rowHeight - topPadding - bottomPadding }
    /// Width of the fade at a scrolling row's edge that has more content beyond it.
    static let edgeFade: CGFloat = 28

    /// Open notch width for a widget row: the row's exact width, clamped to [minOpenWidth, maxWidth].
    static func openWidth(_ widgets: [NookWidget], separatorSpacing: CGFloat, maxWidth: CGFloat) -> CGFloat {
        min(max(rowWidth(widgets, separatorSpacing: separatorSpacing), minOpenWidth), max(maxWidth, minOpenWidth))
    }

    /// Grid cells per widget.
    static func cells(of widget: NookWidget) -> CGFloat {
        switch widget {
        case .calendar:  return 4.4   // 220 pt: 7-day strip + event list
        case .media:     return 5     // 250 pt (.doubleWide)
        case .shortcuts: return ShortcutsWidgetLayout.shared.preferredCells()
        case .mirror:    return MirrorWidgetLayout.shared.preferredCells()  // camera aspect ratio × row height
        case .notes:     return 4     // 200 pt
        case .quickApps: return QuickAppsWidgetLayout.shared.preferredCells()
        case .timer:     return 3.4   // 170 pt
        #if canImport(FanControlKit) // fan-control-integration.md (b): 2x1 = 100 pt, double-wide = 250 pt
        case .fanControl:
            return CGFloat(widget.prefs.gridSizeType.rawValue)
        #endif
        case .clipboard: return 4     // 200 pt: icon + two text lines + time
        case .menuBarItems: return 5  // 250 pt: grid of hidden menu bar item images
        case .reminders: return 4     // 200 pt
        case .storage:   return StorageWidgetLayout.cells  // 200 pt: two rings per row
        case .systemStats: return SystemStatsWidgetSettings.cells  // 250 pt
        case .capture:   return 4     // 200 pt: three capture tiles + record row + delay chips
        case .nextUp: return 5        // 250 pt: title + countdown + Join button
        #if canImport(FanControlKit) // fan-control-integration.md (b): Temperature widget, 250 pt
        case .temperature: return 5
        #endif
        case .batteries: return BatteriesWidgetLayout.preferredCells()  // 200 pt, 400 pt (two columns) above 5 devices
        case .calculator: return 5    // 250 pt: field + result + history
        case .pomodoro: return 4      // 200 pt: phase + today, ring, task field, controls
        case .bluetooth: return BluetoothWidgetLayout.cells   // 200 pt: device list
        case .weather:   return 4     // 200 pt: macOS small Weather tile
        case .network:   return 4     // 200 pt: interface, addresses, throughput sparkline
        case .audioDevices: return AudioDevicesWidgetLayout.preferredCells()  // 400 pt (outputs | inputs), 200 pt outputs only
        case .worldClocks: return WorldClockWidgetLayout.preferredCells()  // one 84 pt tile per clock (104 pt with seconds)
        case .keepAwake: return 4     // 200 pt: ring + countdown + four duration chips
        case .colorPicker: return 4   // 200 pt: swatch + value + 2 rows of 6 recent colours
        case .downloads: return DownloadsWidgetLayout.cells  // 250 pt: thumbnail + name + size / progress
        case .usage:     return 5     // 250 pt: today + 7-day bars, top 5 apps
        case .displays: return DisplaysWidgetLayout.cells  // 250 pt: one card per display
        }
    }

    static func width(of widget: NookWidget) -> CGFloat {
        (cells(of: widget) * cell).rounded()
    }

    /// Width taken by one separator (gap + hairline + gap).
    static func separatorWidth(_ separatorSpacing: CGFloat) -> CGFloat {
        spacing + 2 * max(separatorSpacing, 0)
    }

    /// Width of the whole widget row (used by NotchView for the open footprint).
    static func rowWidth(_ widgets: [NookWidget]) -> CGFloat {
        rowWidth(widgets, separatorSpacing: SettingsStore[.nookSettings].separatorSpacing)
    }

    static func rowWidth(_ widgets: [NookWidget], separatorSpacing: CGFloat) -> CGFloat {
        guard !widgets.isEmpty else { return 0 }
        return widgets.map(width(of:)).reduce(0, +)
            + separatorWidth(separatorSpacing) * CGFloat(widgets.count - 1)
            + horizontalPadding * 2
    }
}

private struct NookRowAvailableWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 820
}

extension EnvironmentValues {
    /// Width of the open notch the widget row is shown in (set by NotchView).
    var nookRowAvailableWidth: CGFloat {
        get { self[NookRowAvailableWidthKey.self] }
        set { self[NookRowAvailableWidthKey.self] = newValue }
    }
}

struct NookWidgetGrid: View {
    @StoredSetting(.nookSettings) private var nookSettings
    @Environment(\.nookRowAvailableWidth) private var availableWidth
    @Environment(\.notchWindowGeometry) private var windowGeometry
    // F9: pages / drag state (shared) and this window's pointer, trackpad and key handling
    @State private var pager = NookWidgetPager.shared
    @State private var interaction = NookGridInteraction()

    struct EdgeAmounts: Equatable {
        var leading: CGFloat = 0
        var trailing: CGFloat = 0
    }

    /// One mounted widget: where it is in the pages.
    private struct Placement: Identifiable {
        var widget: NookWidget
        var page: Int
        var index: Int
        var id: NookWidget { widget }
    }

    var body: some View {
        let pages = pager.pages(nookSettings)
        let geo = geometry(pages)
        Group {
            if pages.count == 1 && pages[0].isEmpty {
                emptyState
            } else {
                strip(geo)
            }
        }
        // a reader view being replaced reports nil after its successor reported the window: keep it
        // (zero-sized and not hit-testable: AppKit hit testing must find the widgets' controls)
        .background(alignment: .topLeading) {
            NookGridWindowReader { if let w = $0 { interaction.window = w } }
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { interaction.gridFrame = $0 }
        .onChange(of: availableWidth, initial: true) { _, w in interaction.containerWidth = w }
        .onChange(of: windowGeometry?.maxOpenWidth ?? 820, initial: true) { _, w in interaction.maxOpenWidth = w }
        .onAppear {
            interaction.install()
            #if DEBUG
            NookWidgetPagesDebug.install()
            #endif
        }
        .onDisappear { interaction.uninstall() }
    }

    private func geometry(_ pages: [[NookWidget]]) -> NookGridGeometry {
        NookGridGeometry(pages: pages, current: pager.pageIndex(count: pages.count), containerWidth: availableWidth,
                         maxOpenWidth: windowGeometry?.maxOpenWidth ?? 820, separatorSpacing: nookSettings.separatorSpacing,
                         scrollOffsets: interaction.scroll.offsets, swipeOffset: pager.swipeOffset)
    }

    // MARK: Pages

    /// Every page's cells in one container, each placed at its model frame (`NookGridGeometry`, the
    /// numbers hit testing and the drag use): one page is just a strip of one. Two rules:
    ///   - only the pages on screen are mounted (`NookWidgetPager.livePages`: the current page, the
    ///     neighbours while a swipe shows them, the pages of a running page slide), so widgets on
    ///     hidden pages run no onAppear work (the Camera widget would turn the camera on);

    ///     (drag + edge dwell) or adding a page keeps its view and @State (a calculator's input, the
    ///     camera session).
    /// Overflowing pages scroll by hand (`NookGridInteraction.scrollWheel`), with edge fades.
    private func strip(_ geo: NookGridGeometry) -> some View {
        let live = pager.livePages(count: geo.pages.count)
        let placements = live.sorted().flatMap { p in
            geo.pages[p].enumerated().map { Placement(widget: $1, page: p, index: $0) }
        }
        let shift = insertionShift(geo)
        return ZStack(alignment: .topLeading) {
            ForEach(live.sorted().filter { geo.pages[$0].isEmpty }, id: \.self) { p in
                emptyPage
                    .frame(width: geo.pageWidth(p), height: NookWidgetLayout.rowHeight, alignment: .top)
                    .offset(x: geo.pageX(p))
                    .allowsHitTesting(false)
            }
            ForEach(separators(placements, geo), id: \.key) { sep in
                separator
                    .frame(height: NookWidgetLayout.cellHeight)
                    .pageMask(page: sep.page, geometry: geo, at: sep.x, fade: edgeAmounts(sep.page, geo), unmasked: false)
                    .offset(x: sep.x, y: NookWidgetLayout.topPadding)
                    .allowsHitTesting(false)
            }
            ForEach(placements) { item in
                cell(item, geometry: geo)
                    .transition(.asymmetric(insertion: .offset(x: shift), removal: .identity))
            }
        }
        .frame(width: availableWidth, height: NookWidgetLayout.rowHeight, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .overlay(alignment: .top) {
            if geo.isPaged {
                pageDots(count: geo.pages.count, current: geo.current)
                    .offset(y: NookWidgetLayout.topPadding + NookWidgetLayout.cellHeight)
            }
        }
    }

    /// Pages mounted for a page slide come in from where they would have been before it (else they
    /// would appear at their final place while the others slide).
    private func insertionShift(_ geo: NookGridGeometry) -> CGFloat {
        guard let from = pager.transitionFrom, from != geo.current, geo.pages.indices.contains(from) else { return 0 }
        let w = geo.pageWidths
        return NookPagesModel.pageOffset(widths: w, current: geo.current) - NookPagesModel.pageOffset(widths: w, current: from)
            + pager.transitionSwipe
    }

    private struct Separator {
        var page: Int
        var index: Int
        var x: CGFloat
        /// Stable across frames (the x animates), so a separator moves instead of being replaced.
        var key: String { "\(page)-\(index)" }
    }

    /// The hairlines between neighbouring cells of the mounted pages (leading x of each gap).
    private func separators(_ placements: [Placement], _ geo: NookGridGeometry) -> [Separator] {
        placements.filter { $0.index > 0 }.map { item in
            let f = geo.cellFrame(page: item.page, index: item.index)
            return Separator(page: item.page, index: item.index, x: f.minX - geo.gap)
        }
    }

    private func edgeAmounts(_ p: Int, _ geo: NookGridGeometry) -> EdgeAmounts {
        let hidden = geo.hiddenContent(p)
        return EdgeAmounts(leading: hidden.leading, trailing: hidden.trailing)
    }

    /// One widget at its slot; the lifted one follows the pointer (its slot moves with the live
    /// reflow, the offset is computed from the same model change, so the two cancel out on screen).
    /// Clipped to its page (with the page's edge fades) unless lifted.
    private func cell(_ item: Placement, geometry geo: NookGridGeometry) -> some View {
        let widget = item.widget
        let lifted = pager.dragged == widget && pager.dragOwner == interaction.id
        let slot = geo.cellFrame(page: item.page, index: item.index)
        let lift = lifted ? liftOffset(widget, geometry: geo) : .zero
        return NookWidgetContentView(widget: widget)
            .frame(width: NookWidgetLayout.width(of: widget), height: NookWidgetLayout.cellHeight, alignment: .top)
            .clipped()
            // where press-and-hold lifts this widget (its header label), in cell coordinates
            .overlayPreferenceValue(NookWidgetLiftHandlesKey.self) { anchors in
                GeometryReader { proxy in
                    let rects = anchors.map { proxy[$0] }
                    Color.clear.onChange(of: rects, initial: true) { _, r in interaction.liftHandles[widget] = r }
                }
                .allowsHitTesting(false)
            }
            .pageMask(page: item.page, geometry: geo, at: slot.minX, fade: edgeAmounts(item.page, geo), unmasked: lifted)
            .scaleEffect(lifted ? 1.04 : 1)
            .shadow(color: .black.opacity(lifted ? 0.55 : 0), radius: lifted ? 14 : 0, y: lifted ? 6 : 0)
            .offset(x: slot.minX + lift.width, y: slot.minY + lift.height)
            .allowsHitTesting(item.page == geo.current || lifted)
            .zIndex(lifted ? 1 : 0)
    }

    private func liftOffset(_ widget: NookWidget, geometry geo: NookGridGeometry) -> CGSize {
        guard let slot = geo.frame(of: widget) else { return .zero }
        let x = pager.dragPoint.x - pager.grabOffset.width - slot.minX
        let y = pager.dragPoint.y - pager.grabOffset.height - slot.minY
        return CGSize(width: x, height: min(max(y, -24), 24))
    }

    /// iOS-style page dots below the widgets (in the row's bottom padding); click to go to a page.
    private func pageDots(count: Int, current: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { p in
                Button {
                    pager.show(page: p, count: count)
                } label: {
                    Circle()
                        .fill(Color.white.opacity(p == current ? 0.9 : 0.3))
                        .frame(width: 6, height: 6)
                        .frame(width: 14, height: NookWidgetLayout.bottomPadding)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Page \(p + 1) of \(count)"))
            }
        }
        .padding(.horizontal, 6)
        .animation(.easeInOut(duration: 0.2), value: current)
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1)
            .padding(.vertical, 18)
            .padding(.horizontal, (NookWidgetLayout.separatorWidth(nookSettings.separatorSpacing) - 1) / 2)
    }

    /// A page without widgets (added in Settings, or emptied by dragging): a drop target.
    private var emptyPage: some View {
        VStack(spacing: 4) {
            Image(systemName: "square.dashed")
                .font(.title2)
            Text("Empty Page")
                .font(.headline)
            Text("Drag a widget here")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.white.opacity(0.7))
        .frame(width: NookWidgetLayout.minOpenWidth - 2 * NookWidgetLayout.horizontalPadding, height: NookWidgetLayout.cellHeight)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .padding(.top, NookWidgetLayout.topPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.grid.2x2")
                .font(.title2)
            Text("No widgets")
                .font(.headline)
            Text("Add widgets in Settings ▸ Nook ▸ Widgets")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Open Settings") {
                NookSettingsNavigation.shared.tab = .widgets
                WindowsManager.shared.showSettings(pane: AppSettings.PaneIdentifier("nook"))
            }
            .buttonStyle(NookCapsuleButtonStyle())
            .padding(.top, 4)
        }
        .foregroundStyle(.white.opacity(0.8))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .dark)
    }
}

private extension View {
    /// Clips a view of page `p` placed at grid x `x` to that page (so an overflowing or neighbouring
    /// page never draws over another), with the page's edge fades. `unmasked` (the lifted widget)
    /// keeps the same structure with a mask that covers everything, so lifting never changes the
    /// view's identity.
    func pageMask(page p: Int, geometry geo: NookGridGeometry, at x: CGFloat,
                  fade: NookWidgetGrid.EdgeAmounts, unmasked: Bool) -> some View {
        let huge: CGFloat = 20_000
        let width = unmasked ? huge : geo.pageWidth(p)
        let dx = unmasked ? -huge / 2 : geo.pageX(p) - x
        return mask(alignment: .topLeading) {
            NookWidgetGrid.edgeFadeMask(unmasked ? NookWidgetGrid.EdgeAmounts() : fade)
                .frame(width: width, height: NookWidgetLayout.rowHeight + 2 * 60)
                .offset(x: dx, y: -60)
        }
    }
}

extension NookWidgetGrid {
    /// Opaque in the middle, fading out over `edgeFade` at an edge with hidden content (the fade
    /// grows in over the first points scrolled, so the row's own padding is never faded at rest).
    static func edgeFadeMask(_ hidden: EdgeAmounts) -> some View {
        let fade = NookWidgetLayout.edgeFade
        let lead = min(hidden.leading, fade), trail = min(hidden.trailing, fade)
        return HStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(0), .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: lead)
            Rectangle().fill(.black)
            LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .leading, endPoint: .trailing)
                .frame(width: trail)
        }
    }
}

/// F9: reports the hosting window (the notch window) to the grid's event handling.
private struct NookGridWindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.onWindow = onWindow
    }

    final class ReaderView: NSView {
        var onWindow: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindow?(window)
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// The widget → view switch (fan-control-integration.md (b) adds `case .fanControl` here).
struct NookWidgetContentView: View {
    let widget: NookWidget

    var body: some View {
        switch widget {
        case .calendar:  CalendarWidgetView()
        case .media:     MediaPlayerWidgetView()
        case .shortcuts: ShortcutsWidgetView()
        case .mirror:    MirrorWidgetView()
        case .notes:     NotesWidgetView()
        case .quickApps: QuickAppsWidgetView()
        case .timer:     TimerWidgetView()
        #if canImport(FanControlKit) // fan-control-integration.md (b)
        case .fanControl: FanControlWidgetView()
        #endif
        case .clipboard: ClipboardWidgetView()
        case .menuBarItems: MenuBarItemsWidgetView()
        case .reminders: RemindersWidgetView()
        case .storage:   StorageWidgetView()
        case .systemStats: SystemStatsWidgetView()
        case .capture:   CaptureWidgetView()
        case .nextUp: NextUpWidgetView()
        #if canImport(FanControlKit) // fan-control-integration.md (b)
        case .temperature: FanControlTemperatureWidgetView()
        #endif
        case .batteries: BatteriesWidgetView()
        case .calculator: CalculatorWidgetView()
        case .pomodoro: PomodoroWidgetView()
        case .bluetooth: BluetoothWidgetView()
        case .weather:   WeatherWidgetView()
        case .network:   NetworkWidgetView()
        case .audioDevices: AudioDevicesWidgetView()
        case .worldClocks: WorldClockWidgetView()
        case .keepAwake: KeepAwakeWidgetView()
        case .colorPicker: ColorPickerWidgetView()
        case .downloads: DownloadsWidgetView()
        case .usage:     UsageWidgetView()
        case .displays: DisplaysWidgetView()
        }
    }
}
