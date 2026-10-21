// F9 (widget pages): page state, drag-to-reorder state and the open notch's pointer / trackpad /
// keyboard handling for the Nook widget grid (NookWidgetGrid.swift).
//
// - `NookSettings.pages` binds the pure model (NookWidgetPagesModel.swift) to the stored settings:
//   `widgets` stays the flat list of every widget, `widgetPages` the optional page split.
// - `NookWidgetPager.shared` (one for all screens): the page shown in the open notch, the swipe
//   translation, and while a widget is dragged the working copy of the pages (`draftPages`, the
//   live reflow; committed to the settings on drop). NotchView sizes the open notch from
//   `visibleWidgets(_:)` (the current page, or the draft of it while dragging) and the window from
//   `NookWidgetLayout.windowOpenWidth` (the widest page, so paging never shrinks the window under
//   an animating notch). NotchViewModel keeps the notch open while `isInteracting`.
// - `NookGridInteraction` (one per grid, i.e. per open notch window) owns an AppKit local event
//   monitor for that window:
//     * lift a widget, then drag to reorder (others reflow live), towards the notch's left / right
//       edge to move it to the previous / next page (after `edgeDwell`), release to drop (a page
//       the drag emptied is removed; pages already empty stay as drop targets); Escape cancels.
//       Two ways to lift, neither of which touches presses on the widgets' controls:
//         - ⌥-press anywhere on a widget lifts it at once (the widget never sees that press);
//         - press and hold (`liftDelay`, moving less than `liftSlop`) on a lift handle: the
//           widget's header label (`NookWidgetHeaderLabel` marks itself with
//           `.nookWidgetLiftHandle()`; other non-interactive chrome can opt in the same way).
//           Only a press on a handle is held back; released or moved first, it is replayed and the
//           widget gets a normal click / drag.
//       Every other press reaches the widget immediately, exactly as without pages.
//     * two-finger horizontal swipe on the trackpad pages (content follows the fingers, rubber band
//       past the ends; an overflowing page scrolls first — by hand, `NookGridScroll`, since the
//       grid lays the cells out itself — and pages only from its edge); a mouse's horizontal wheel
//       (Shift-scroll) scrolls an overflowing page, else steps pages. A gesture's end is always
//       handled (also mid-drag, or after the pointer left the window); a claimed swipe with no
//       samples for `swipeTimeout` is cancelled, so the notch can always close again;
//     * ← / → page when the notch window is key and no text is being edited.
//   Nothing is handled with one page and fewer than two widgets (single-page Nook unchanged).
import AppKit
import Observation
import SwiftUI

// MARK: - Settings binding

extension NookSettings {
    /// The widget pages (always at least one). Setting it updates `widgets` (flat, page order) and
    /// `widgetPages` (nil when there is a single page, i.e. stored exactly as before pages existed).
    var pages: [[NookWidget]] {
        get { NookPagesModel.pages(stored: widgetPages, flat: widgets) }
        set {
            let stored = NookPagesModel.storage(for: newValue)
            widgets = stored.flat
            widgetPages = stored.pages
        }
    }

    /// Settings "Add to Nook": the widget goes to the end of the last page.
    mutating func addWidget(_ widget: NookWidget) {
        pages = NookPagesModel.adding(widget, to: pages)
    }

    /// Settings "Remove from Nook": removed from its page too (re-adding puts it on the last page).
    mutating func removeWidget(_ widget: NookWidget) {
        pages = NookPagesModel.removing(widget, from: pages)
    }
}

extension NookWidgetLayout {
    /// Open width of the widest page: the notch window is fitted to this so that paging (which
    /// animates the notch between page widths) never shrinks the window under the notch.
    static func windowOpenWidth(_ settings: NookSettings, maxWidth: CGFloat) -> CGFloat {
        let pages = NookWidgetPager.shared.pages(settings)
        return pages.map { openWidth($0, separatorSpacing: settings.separatorSpacing, maxWidth: maxWidth) }.max()
            ?? openWidth([], separatorSpacing: settings.separatorSpacing, maxWidth: maxWidth)
    }
}

// MARK: - Shared page / drag state

@Observable
final class NookWidgetPager {
    static let shared = NookWidgetPager()

    /// Page shown in the open notch (clamped to the pages on use).
    var currentPage = 0
    /// Interactive swipe translation of the page strip (content follows the fingers).
    var swipeOffset: CGFloat = 0
    /// While a widget is lifted: the pages with the live reorder applied (committed on drop).
    var draftPages: [[NookWidget]]?
    /// The lifted widget.
    var dragged: NookWidget?
    /// Pointer in the owning grid's coordinate space, and where in the widget it was grabbed.
    var dragPoint: CGPoint = .zero
    var grabOffset: CGSize = .zero
    /// The grid (window) that owns the drag; other screens' grids show the reflow without the lift.
    @ObservationIgnored var dragOwner: ObjectIdentifier?
    /// The pages when the widget was lifted (pages the drag empties are removed on drop).
    @ObservationIgnored private var liftPages: [[NookWidget]] = []
    @ObservationIgnored var isSwiping = false
    /// Time of the last sample of the claimed swipe (a swipe whose end never arrives stops
    /// counting as interaction after `swipeTimeout`).
    @ObservationIgnored var lastSwipeSample: TimeInterval = 0
    @ObservationIgnored private var settleUntil: TimeInterval = 0
    /// Pages kept mounted besides the current one while the strip slides between pages (the grid
    /// mounts only the current page otherwise, plus its neighbours while a swipe shows them).
    var transitionPages: Set<Int> = []
    /// The page and swipe offset a running page transition started from (the grid slides pages
    /// that are mounted for the transition in from where they would have been).
    @ObservationIgnored private(set) var transitionFrom: Int?
    @ObservationIgnored private(set) var transitionSwipe: CGFloat = 0
    @ObservationIgnored private var transitionGeneration = 0

    /// A claimed swipe without samples for this long is over (its `.ended` was lost).
    static let swipeTimeout: TimeInterval = 2.5
    /// How long the pages of a transition stay mounted (the page spring settles within it).
    static let transitionDuration: TimeInterval = 0.6

    static let pageAnimation = Animation.spring(response: 0.38, dampingFraction: 0.86)
    static let reflowAnimation = Animation.spring(response: 0.3, dampingFraction: 0.8)
    static let liftAnimation = Animation.spring(response: 0.25, dampingFraction: 0.7)

    /// F9: a widget is being dragged, a swipe is in progress, or a page / drop animation is still
    /// running — the notch must not close (NotchViewModel.notchIsBusy).
    var isInteracting: Bool {
        let now = ProcessInfo.processInfo.systemUptime
        return dragged != nil || (isSwiping && now - lastSwipeSample < Self.swipeTimeout) || now < settleUntil
    }

    /// Keep `isInteracting` true for a moment (an animation that just started).
    func settle(_ seconds: TimeInterval = 0.45) {
        settleUntil = max(settleUntil, ProcessInfo.processInfo.systemUptime + seconds)
    }

    /// Pages to show: the drag's working copy, else the stored pages.
    func pages(_ settings: NookSettings) -> [[NookWidget]] {
        draftPages ?? settings.pages
    }

    func pageIndex(count: Int) -> Int {
        NookPagesModel.clampPage(currentPage, count: count)
    }

    /// Widgets of the page the open notch shows (NotchView sizes the open notch from these).
    func visibleWidgets(_ settings: NookSettings) -> [NookWidget] {
        let pages = pages(settings)
        return pages[pageIndex(count: pages.count)]
    }

    /// Show page `page` (animated like iOS: the strip slides, the notch resizes to the page).
    func show(page: Int, count: Int, animated: Bool = true) {
        let target = NookPagesModel.clampPage(page, count: count)
        let from = pageIndex(count: count)
        settle()
        if animated {
            withAnimation(Self.pageAnimation) {
                beginTransition(from: from, to: target, count: count)
                currentPage = target
                swipeOffset = 0
            }
        } else {
            currentPage = target
            swipeOffset = 0
        }
    }

    /// Keeps the pages on screen during a page change mounted until it has settled: the page
    /// left, the page shown and, after a swipe, the neighbours it revealed. Call inside the
    /// change's `withAnimation`, so the pages it mounts slide in with it.
    func beginTransition(from: Int, to target: Int, count: Int) {
        var keep: Set<Int> = [from, target]
        if swipeOffset != 0 { keep.formUnion([from - 1, from + 1]) }
        keep = keep.filter { (0..<count).contains($0) }
        transitionFrom = from
        transitionSwipe = swipeOffset
        if !keep.isSubset(of: transitionPages) { transitionPages.formUnion(keep) }
        transitionGeneration &+= 1
        let generation = transitionGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.transitionDuration) { [weak self] in
            guard let self, generation == self.transitionGeneration else { return }
            self.transitionFrom = nil
            self.transitionSwipe = 0
            guard !self.transitionPages.isEmpty else { return }
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { self.transitionPages = [] }
        }
    }

    /// Pages whose widgets the grid mounts: the current one, the pages of a running transition,
    /// the neighbours while a swipe shows them, and the dragged widget's page.
    func livePages(count: Int) -> Set<Int> {
        let current = pageIndex(count: count)
        var live: Set<Int> = [current]
        live.formUnion(transitionPages)
        if swipeOffset != 0 { live.formUnion([current - 1, current + 1]) }
        return live.filter { (0..<count).contains($0) }
    }

    // MARK: Drag

    func beginDrag(_ widget: NookWidget, pages: [[NookWidget]], point: CGPoint, grab: CGSize, owner: ObjectIdentifier) {
        dragOwner = owner
        grabOffset = grab
        dragPoint = point
        draftPages = pages
        liftPages = pages
        withAnimation(Self.liftAnimation) { dragged = widget }
    }

    /// Commit (or cancel) the drag; the lifted widget settles into its slot.
    func endDrag(commit: Bool) {
        guard dragged != nil else { return }
        let draft = draftPages
        settle()
        withAnimation(Self.reflowAnimation) {
            if commit, let draft {
                // a page the drag emptied goes away (pages that were already empty stay)
                let pruned = NookPagesModel.pruningPagesEmptied(from: liftPages, to: draft, current: currentPage)
                currentPage = pruned.current
                var settings = SettingsStore[.nookSettings]
                if settings.pages != pruned.pages {
                    settings.pages = pruned.pages
                    SettingsStore[.nookSettings] = settings
                }
            }
            draftPages = nil
            dragged = nil
            dragOwner = nil
        }
    }
}

// MARK: - Grid geometry (pure; in the grid view's coordinate space)

/// Where the pages and widget cells of the Nook grid are, computed from the model (the same numbers
/// the grid lays out with), so hit testing and the drag's slot search never depend on measuring
/// views mid-animation.
struct NookGridGeometry {
    var pages: [[NookWidget]]
    var current: Int
    /// Width of the grid (the open notch's width = the current page's open width).
    var containerWidth: CGFloat
    var maxOpenWidth: CGFloat
    var separatorSpacing: CGFloat
    /// Horizontal scroll offset of overflowing pages (clamped on use: `scroll(_:)`).
    var scrollOffsets: [Int: CGFloat] = [:]
    var swipeOffset: CGFloat = 0

    var isPaged: Bool { pages.count > 1 }
    var gap: CGFloat { NookWidgetLayout.separatorWidth(separatorSpacing) }

    func pageWidth(_ p: Int) -> CGFloat {
        guard isPaged else { return containerWidth }
        if p == current { return containerWidth }
        return NookWidgetLayout.openWidth(pages[p], separatorSpacing: separatorSpacing, maxWidth: maxOpenWidth)
    }

    var pageWidths: [CGFloat] { pages.indices.map(pageWidth) }

    /// Leading x of page `p` in the grid (the current page at 0, plus the swipe).
    func pageX(_ p: Int) -> CGFloat {
        guard isPaged else { return 0 }
        let w = pageWidths
        return NookPagesModel.pageOffset(widths: w, current: p) - NookPagesModel.pageOffset(widths: w, current: current) + swipeOffset
    }

    func rowWidth(_ p: Int) -> CGFloat {
        NookWidgetLayout.rowWidth(pages[p], separatorSpacing: separatorSpacing)
    }

    func overflows(_ p: Int) -> Bool {
        rowWidth(p) > pageWidth(p) + 0.5
    }

    /// How far an overflowing page scrolls (0 for a page that fits).
    func maxScroll(_ p: Int) -> CGFloat {
        overflows(p) ? max(rowWidth(p) - pageWidth(p), 0) : 0
    }

    /// Page `p`'s scroll offset, clamped to its current content.
    func scroll(_ p: Int) -> CGFloat {
        min(max(scrollOffsets[p] ?? 0, 0), maxScroll(p))
    }

    /// Content hidden beyond the leading / trailing edge of page `p` (drives the edge fades and
    /// whether a swipe scrolls the page or pages).
    func hiddenContent(_ p: Int) -> (leading: CGFloat, trailing: CGFloat) {
        let offset = scroll(p)
        return (offset, maxScroll(p) - offset)
    }

    /// Leading x of page `p`'s first cell, relative to the page.
    func rowStart(_ p: Int) -> CGFloat {
        if overflows(p) { return NookWidgetLayout.horizontalPadding - scroll(p) }
        return (pageWidth(p) - rowWidth(p)) / 2 + NookWidgetLayout.horizontalPadding
    }

    func cellFrame(page p: Int, index i: Int) -> CGRect {
        let widths = pages[p].map(NookWidgetLayout.width(of:))
        let x = NookPagesModel.cellOrigins(widths: widths, gap: gap)[i]
        return CGRect(x: pageX(p) + rowStart(p) + x, y: NookWidgetLayout.topPadding,
                      width: widths[i], height: NookWidgetLayout.cellHeight)
    }

    func frame(of widget: NookWidget) -> CGRect? {
        NookPagesModel.location(of: widget, in: pages).map { cellFrame(page: $0.page, index: $0.index) }
    }

    /// The widget cell of the current page under `point` (only what is visible in the grid).
    func hit(_ point: CGPoint) -> (widget: NookWidget, frame: CGRect)? {
        guard point.x >= 0, point.x <= containerWidth, pages.indices.contains(current) else { return nil }
        for i in pages[current].indices {
            let f = cellFrame(page: current, index: i)
            if f.contains(point) { return (pages[current][i], f) }
        }
        return nil
    }

    /// Slot on page `p` for the dragged widget whose leading edge is at `leadingX` (grid space).
    func insertionIndex(page p: Int, dragged: NookWidget, leadingX: CGFloat) -> Int {
        let others = pages[p].filter { $0 != dragged }.map(NookWidgetLayout.width(of:))
        let w = NookWidgetLayout.width(of: dragged)
        // the row with the dragged widget included (its width does not depend on the slot)
        var withDragged = pages[p].filter { $0 != dragged }
        withDragged.append(dragged)
        var probe = self
        probe.pages[p] = withDragged
        let start = probe.pageX(p) + probe.rowStart(p)
        return NookPagesModel.insertionIndex(centerX: leadingX + w / 2 - start, draggedWidth: w, others: others, gap: gap)
    }
}

// MARK: - Per-window interaction (event monitor)

/// Scroll offsets of the overflowing pages of one grid (observed by the grid view; the pages are
/// laid out by hand, so they scroll by hand too: `NookGridInteraction.scrollWheel`).
@Observable
final class NookGridScroll {
    var offsets: [Int: CGFloat] = [:]
}

final class NookGridInteraction {
    static let liftDelay: TimeInterval = 0.45
    static let liftSlop: CGFloat = 4
    static let edgeZone: CGFloat = 28
    static let edgeDwell: TimeInterval = 0.55

    weak var window: NSWindow?
    /// The grid's frame in the window's SwiftUI global space (top-left origin).
    var gridFrame: CGRect = .zero
    var containerWidth: CGFloat = 0
    var maxOpenWidth: CGFloat = 820
    let scroll = NookGridScroll()
    var scrollOffsets: [Int: CGFloat] { scroll.offsets }
    /// Lift handles of each widget, in the widget cell's coordinates (`.nookWidgetLiftHandle()`).
    var liftHandles: [NookWidget: [CGRect]] = [:]

    private var pager: NookWidgetPager { .shared }
    private var monitor: Any?

    // hold → lift
    private var heldDown: NSEvent?
    private var holdPoint: CGPoint = .zero
    private var holdTimer: Timer?

    // edge dwell while dragging
    private var edgeTimer: Timer?
    private var edgeSide = 0

    // swipe
    /// `claimed`: the gesture pages; `scrolling`: it scrolls the overflowing current page.
    private enum SwipeState { case idle, undecided(CGFloat, CGFloat), claimed, scrolling, ignored }
    private enum Momentum { case none, swipe, scroll }
    private var swipe: SwipeState = .idle
    private var swipeTranslation: CGFloat = 0
    private var swipeVelocity: CGFloat = 0
    private var lastSwipeTime: TimeInterval = 0
    private var momentum: Momentum = .none
    private var wheelCooldownUntil: TimeInterval = 0
    /// Ends a claimed swipe whose `.ended` / `.cancelled` never reached this monitor.
    private var swipeWatchdog: Timer?

    var id: ObjectIdentifier { ObjectIdentifier(self) }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    func install() {
        guard monitor == nil else { return }
        #if DEBUG
        Self.live.add(self)
        #endif
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .scrollWheel, .keyDown]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    func uninstall() {
        if heldDown != nil { replayHeld() }
        if pager.dragOwner == id { pager.endDrag(commit: true) }
        endSwipe(cancelled: true)
        momentum = .none
        holdTimer?.invalidate(); holdTimer = nil
        stopEdgeDwell()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    // MARK: Model

    private var settings: NookSettings { SettingsStore[.nookSettings] }

    func geometry() -> NookGridGeometry {
        let s = settings
        let pages = pager.pages(s)
        return NookGridGeometry(pages: pages, current: pager.pageIndex(count: pages.count), containerWidth: containerWidth,
                                maxOpenWidth: maxOpenWidth, separatorSpacing: s.separatorSpacing,
                                scrollOffsets: scrollOffsets, swipeOffset: pager.swipeOffset)
    }

    /// Reordering is possible (two widgets, or more than one page).
    private var canArrange: Bool {
        let pages = pager.pages(settings)
        return pages.count > 1 || pages.joined().count > 1
    }

    /// Window event location → grid space.
    func gridPoint(_ event: NSEvent) -> CGPoint {
        let h = window?.contentView?.bounds.height ?? window?.frame.height ?? 0
        return CGPoint(x: event.locationInWindow.x - gridFrame.minX, y: (h - event.locationInWindow.y) - gridFrame.minY)
    }

    // MARK: Dispatch

    private func handle(_ event: NSEvent) -> NSEvent? {
        let dragging = pager.dragOwner == id
        // a gesture this grid took keeps reaching it when the pointer leaves the window, so its end
        // is never lost (a claimed swipe left open would keep the notch from closing)
        guard let window, event.window === window || (dragging && event.type != .scrollWheel)
                || (event.type == .scrollWheel && ownsGesture) else { return event }
        switch event.type {
        case .leftMouseDown: return mouseDown(event)
        case .leftMouseDragged: return mouseDragged(event)
        case .leftMouseUp: return mouseUp(event)
        case .scrollWheel: return scrollWheel(ScrollSample(event), at: gridPoint(event)) ? nil : event
        case .keyDown: return keyDown(event) ? nil : event
        default: return event
        }
    }

    // MARK: Hold, lift, drag, drop

    private func mouseDown(_ event: NSEvent) -> NSEvent? {
        guard heldDown == nil, pager.dragged == nil, canArrange, event.modifierFlags.intersection([.control, .command]).isEmpty
        else { return event }
        let point = gridPoint(event)
        guard let hit = geometry().hit(point) else { return event }
        if event.modifierFlags.contains(.option) {
            // ⌥-press: lift at once; the widget never sees this press or its release
            holdPoint = point
            heldDown = event
            lift()
            return nil
        }
        // plain press: held back only on a lift handle (non-interactive chrome), else delivered now
        let local = CGPoint(x: point.x - hit.frame.minX, y: point.y - hit.frame.minY)
        guard (liftHandles[hit.widget] ?? []).contains(where: { $0.contains(local) }), !isOverAppKitControl(event)
        else { return event }
        heldDown = event
        holdPoint = point
        let timer = Timer(timeInterval: Self.liftDelay, repeats: false) { [weak self] _ in self?.lift() }
        RunLoop.main.add(timer, forMode: .common)
        holdTimer = timer
        return nil
    }

    /// The press lands on an AppKit control or text view (SwiftUI's platform-backed Toggle, Slider,
    /// TextField, Picker, bordered / borderless Button, or an NSViewRepresentable control). Those
    /// run their own mouse-tracking loop on mouse-down, which would wait for a release that was
    /// already dequeued if the press were held back and replayed, so they get it at once (and the
    /// widget cannot be lifted from them).
    private func isOverAppKitControl(_ event: NSEvent) -> Bool {
        guard let content = window?.contentView else { return false }
        let root = content.superview ?? content
        var view = root.hitTest(event.locationInWindow)
        while let v = view, v !== content {
            if v is NSControl || v is NSText { return true }
            view = v.superview
        }
        return false
    }

    private func mouseDragged(_ event: NSEvent) -> NSEvent? {
        if pager.dragOwner == id {
            drag(to: gridPoint(event))
            return nil
        }
        guard heldDown != nil else { return event }
        let p = gridPoint(event)
        if hypot(p.x - holdPoint.x, p.y - holdPoint.y) > Self.liftSlop {
            replayHeld()              // not a long press: the widget gets the press, then this drag
            return event
        }
        return nil
    }

    private func mouseUp(_ event: NSEvent) -> NSEvent? {
        if pager.dragOwner == id {
            stopEdgeDwell()
            pager.endDrag(commit: true)
            return nil
        }
        guard heldDown != nil else { return event }
        replayHeld()                  // a click: the widget gets the press, then this release
        return event
    }

    /// Deliver the held mouse-down to the window now (synchronously, bypassing the local monitors);
    /// the caller then lets the event that decided it was not a long press continue. Re-posting
    /// with NSApp.postEvent is not used: a re-queued mouse event's location is re-derived from
    /// screen coordinates and came back wrong (DEBUG offscreen windows).
    /// A control with its own tracking loop (NSSlider, text selection) runs that loop inside this
    /// call; the deciding event then arrives after its release and is ignored by AppKit.
    private func replayHeld() {
        holdTimer?.invalidate(); holdTimer = nil
        guard let down = heldDown else { return }
        heldDown = nil
        #if DEBUG
        NSLog("[WidgetPages] replaying held mouse-down at %@", NSStringFromPoint(down.locationInWindow))
        #endif
        (down.window ?? window)?.sendEvent(down)
    }

    private func lift() {
        holdTimer = nil
        guard heldDown != nil else { return }
        heldDown = nil                // the widget never sees this press
        let g = geometry()
        guard let hit = g.hit(holdPoint) else { return }
        stopEdgeDwell()               // every drag starts with no edge armed
        pager.beginDrag(hit.widget, pages: g.pages, point: holdPoint,
                        grab: CGSize(width: holdPoint.x - hit.frame.minX, height: holdPoint.y - hit.frame.minY), owner: id)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    func drag(to point: CGPoint) {
        guard let widget = pager.dragged, pager.dragOwner == id else { return }
        pager.dragPoint = point
        let g = geometry()
        guard let from = NookPagesModel.location(of: widget, in: g.pages) else { return }
        let slot = g.insertionIndex(page: g.current, dragged: widget, leadingX: point.x - pager.grabOffset.width)
        if from.page != g.current || from.index != slot {
            withAnimation(NookWidgetPager.reflowAnimation) {
                pager.draftPages = NookPagesModel.move(widget, toPage: g.current, index: slot, in: g.pages)
            }
        }
        updateEdgeDwell(point, geometry: g)
    }

    /// Dwelling near the left / right edge while dragging flips to the previous / next page.
    private func updateEdgeDwell(_ point: CGPoint, geometry g: NookGridGeometry) {
        var side = 0
        if g.isPaged {
            if point.x < Self.edgeZone, g.current > 0 { side = -1 }
            if point.x > containerWidth - Self.edgeZone, g.current < g.pages.count - 1 { side = 1 }
        }
        guard side != edgeSide else { return }
        edgeSide = side
        edgeTimer?.invalidate(); edgeTimer = nil
        guard side != 0 else { return }
        let timer = Timer(timeInterval: Self.edgeDwell, repeats: true) { [weak self] _ in self?.flipPage() }
        RunLoop.main.add(timer, forMode: .common)
        edgeTimer = timer
    }

    /// Stops the edge dwell and forgets the armed side (on drop, cancel, lift and uninstall), so
    /// the next drag into the same edge zone arms the timer again.
    private func stopEdgeDwell() {
        edgeTimer?.invalidate()
        edgeTimer = nil
        edgeSide = 0
    }

    private func flipPage() {
        guard let widget = pager.dragged, pager.dragOwner == id, edgeSide != 0 else { return }
        let g = geometry()
        let target = NookPagesModel.clampPage(g.current + edgeSide, count: g.pages.count)
        guard target != g.current else { stopEdgeDwell(); return }
        // arrive at the near end of the new page (its end when moving back, its start when moving on)
        let others = g.pages[target].filter { $0 != widget }
        let index = edgeSide < 0 ? others.count : 0
        withAnimation(NookWidgetPager.pageAnimation) {
            pager.beginTransition(from: g.current, to: target, count: g.pages.count)
            pager.draftPages = NookPagesModel.move(widget, toPage: target, index: index, in: g.pages)
            pager.currentPage = target
            pager.swipeOffset = 0
        }
        pager.settle()
        // the pointer is now beside the new page's edge: dwell again to keep going
    }

    // MARK: Swipe

    /// A scroll event, separated from NSEvent so DEBUG hooks can inject gestures.
    struct ScrollSample {
        var dx: CGFloat
        var dy: CGFloat
        var precise: Bool
        var phase: NSEvent.Phase
        var momentum: NSEvent.Phase

        init(dx: CGFloat, dy: CGFloat, precise: Bool, phase: NSEvent.Phase, momentum: NSEvent.Phase = []) {
            self.dx = dx; self.dy = dy; self.precise = precise; self.phase = phase; self.momentum = momentum
        }

        init(_ e: NSEvent) {
            self.init(dx: e.scrollingDeltaX, dy: e.scrollingDeltaY, precise: e.hasPreciseScrollingDeltas,
                      phase: e.phase, momentum: e.momentumPhase)
        }
    }

    /// A gesture this grid took (paging or scrolling the current page).
    private var ownsGesture: Bool {
        switch swipe {
        case .claimed, .scrolling: return true
        default: return momentum != .none
        }
    }

    /// Returns true when the event was used for paging or for scrolling an overflowing page (and
    /// must not reach the widgets). Vertical gestures are always left to the widgets.
    func scrollWheel(_ s: ScrollSample, at point: CGPoint) -> Bool {
        let g = geometry()
        // a gesture's end is handled before anything else (also while a widget is dragged), so a
        // claimed swipe is always closed
        if s.momentum.isEmpty, s.phase.contains(.ended) || s.phase.contains(.cancelled) {
            let ended = swipe
            endSwipe(cancelled: s.phase.contains(.cancelled))
            switch ended {
            case .claimed: momentum = .swipe; return true
            case .scrolling: momentum = .scroll; return true
            default: momentum = .none; return false
            }
        }
        // momentum after a gesture this grid took: a swipe's is swallowed, a scroll's keeps scrolling
        if !s.momentum.isEmpty {
            let mode = momentum
            if s.momentum.contains(.ended) || s.momentum.contains(.cancelled) { momentum = .none }
            switch mode {
            case .swipe: return true
            case .scroll: scrollPage(g.current, by: -s.dx, geometry: g); return true
            case .none: return false
            }
        }
        if s.phase.isEmpty {
            // a mouse wheel: a horizontal tick scrolls an overflowing page first, else steps pages;
            // vertical is left to the widgets
            guard abs(s.dx) > abs(s.dy), abs(s.dx) > 0, gridContains(point) else { return false }
            let step = s.precise ? s.dx : s.dx * Self.wheelLineWidth
            if g.overflows(g.current), canScroll(g.current, by: -step, geometry: g) {
                withAnimation(.easeOut(duration: 0.15)) { scrollPage(g.current, by: -step, geometry: g) }
                return true
            }
            guard !s.precise, g.isPaged, pager.dragged == nil else { return false }
            let now = ProcessInfo.processInfo.systemUptime
            if now >= wheelCooldownUntil {
                wheelCooldownUntil = now + 0.35
                pager.show(page: g.current + (s.dx < 0 ? 1 : -1), count: g.pages.count)
            }
            return true
        }
        if s.phase.contains(.mayBegin) || s.phase.contains(.began) {
            // a new gesture while the previous one is still open (its end was lost): close it first
            if case .claimed = swipe { endSwipe(cancelled: true) }
            swipe = .idle
            momentum = .none
            guard gridContains(point) else { swipe = .ignored; return false }
            swipe = .undecided(s.dx, s.dy)
            return false
        }
        if s.phase.contains(.changed) {
            switch swipe {
            case .undecided(let ax, let ay):
                let x = ax + s.dx, y = ay + s.dy
                guard hypot(x, y) > 6 else { swipe = .undecided(x, y); return false }
                guard abs(x) > abs(y) * 1.2 else { swipe = .ignored; return false }
                let mayPage = g.isPaged && pager.dragged == nil && pageMayTake(x, geometry: g)
                if g.overflows(g.current) && !mayPage {
                    swipe = .scrolling
                    scrollPage(g.current, by: -x, geometry: g)
                    return true
                }
                guard mayPage else { swipe = .ignored; return false }
                swipe = .claimed
                pager.isSwiping = true
                swipeTranslation = x
                swipeVelocity = 0
                lastSwipeTime = ProcessInfo.processInfo.systemUptime
                pager.lastSwipeSample = lastSwipeTime
                pager.swipeOffset = NookPagesModel.rubberBand(swipeTranslation, current: g.current, count: g.pages.count)
                startSwipeWatchdog()
                return true
            case .claimed:
                let now = ProcessInfo.processInfo.systemUptime
                let dt = max(now - lastSwipeTime, 1.0 / 240)
                swipeVelocity = 0.7 * swipeVelocity + 0.3 * (s.dx / CGFloat(dt))
                lastSwipeTime = now
                pager.lastSwipeSample = now
                swipeTranslation += s.dx
                pager.swipeOffset = NookPagesModel.rubberBand(swipeTranslation, current: g.current, count: g.pages.count)
                return true
            case .scrolling:
                scrollPage(g.current, by: -s.dx, geometry: g)
                return true
            default:
                return false
            }
        }
        return false
    }

    /// Points a mouse wheel's line step scrolls an overflowing page.
    static let wheelLineWidth: CGFloat = 12

    private func canScroll(_ p: Int, by delta: CGFloat, geometry g: NookGridGeometry) -> Bool {
        let hidden = g.hiddenContent(p)
        return delta > 0 ? hidden.trailing >= 1 : hidden.leading >= 1
    }

    /// Scrolls page `p` by `delta` points (clamped to its content).
    private func scrollPage(_ p: Int, by delta: CGFloat, geometry g: NookGridGeometry) {
        guard g.pages.indices.contains(p) else { return }
        let next = min(max(g.scroll(p) + delta, 0), g.maxScroll(p))
        if next != scroll.offsets[p] { scroll.offsets[p] = next }
    }

    private func endSwipe(cancelled: Bool) {
        swipeWatchdog?.invalidate(); swipeWatchdog = nil
        defer { swipe = .idle; pager.isSwiping = false }
        guard case .claimed = swipe else { return }
        let g = geometry()
        let target = cancelled ? g.current
            : NookPagesModel.swipeTarget(current: g.current, count: g.pages.count, translation: swipeTranslation,
                                         velocity: swipeVelocity, pageWidth: containerWidth)
        pager.show(page: target, count: g.pages.count)
    }

    /// Backstop for a claimed swipe whose end another monitor consumed: once no sample arrived for
    /// `NookWidgetPager.swipeTimeout`, it is cancelled (the strip settles back, the notch may close).
    private func startSwipeWatchdog() {
        swipeWatchdog?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard case .claimed = self.swipe else { self.swipeWatchdog?.invalidate(); self.swipeWatchdog = nil; return }
            if ProcessInfo.processInfo.systemUptime - self.lastSwipeTime >= NookWidgetPager.swipeTimeout {
                self.endSwipe(cancelled: true)
                self.momentum = .none
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        swipeWatchdog = timer
    }

    private func gridContains(_ point: CGPoint) -> Bool {
        point.x >= 0 && point.y >= 0 && point.x <= gridFrame.width && point.y <= gridFrame.height
    }

    /// An overflowing page scrolls first: it pages only once scrolled to the edge being pulled.
    private func pageMayTake(_ dx: CGFloat, geometry g: NookGridGeometry) -> Bool {
        guard g.overflows(g.current) else { return true }
        let hidden = g.hiddenContent(g.current)
        return dx > 0 ? hidden.leading < 1 : hidden.trailing < 1
    }

    // MARK: Keys

    /// ← / → page; Escape cancels a drag. Returns true when handled.
    func keyDown(_ event: NSEvent) -> Bool {
        handleKey(event.keyCode, modifiers: event.modifierFlags)
    }

    func handleKey(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) -> Bool {
        if keyCode == 53, pager.dragOwner == id {           // Escape
            stopEdgeDwell()
            pager.endDrag(commit: false)
            return true
        }
        guard keyCode == 123 || keyCode == 124,
              modifiers.intersection([.command, .option, .control, .shift]).isEmpty,
              !((window?.isKeyWindow ?? false) && window?.firstResponder is NSText) else { return false }
        let g = geometry()
        guard g.isPaged, pager.dragged == nil else { return false }
        pager.show(page: g.current + (keyCode == 124 ? 1 : -1), count: g.pages.count)
        return true
    }
}

// MARK: - Lift handles

/// Frames of the non-interactive parts of a widget that a press-and-hold lifts (header labels).
struct NookWidgetLiftHandlesKey: PreferenceKey {
    static let defaultValue: [Anchor<CGRect>] = []
    static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    /// F9: marks this (non-interactive) view as a lift handle of the Nook widget it is in: press
    /// and hold on it lifts the widget for reordering. Do not put it on a control — a press on a
    /// handle reaches the view only when it is released or moved before `liftDelay`.
    func nookWidgetLiftHandle() -> some View {
        anchorPreference(key: NookWidgetLiftHandlesKey.self, value: .bounds) { [$0] }
    }
}
