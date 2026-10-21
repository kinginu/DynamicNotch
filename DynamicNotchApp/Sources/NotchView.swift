import AppKit
import SwiftUI
#if canImport(FanControlKit)
import FanControlKit
#endif

// MARK: - NotchView

// General settings NotchView reads that GeneralSettings does not have (yet): fixed defaults.
enum NotchViewFlags {
    static var liquidGlass: Bool { false }
    static var widgetWidth: CGFloat { 0 }
    static var disabled: Bool { false }
    static var isNonNotch: Bool { false }
    static var isNonNotchAndDisabled: Bool { false }
}

/// One screen's notch: the closed notch (live activities beside the camera housing) and the open
/// Nook / tray, drawn in a fixed canvas and animated by one footprint (see `body`).
struct NotchView: View {
    @State var viewModel: NotchViewModel

    /// Hardware notch size of this screen.
    @Environment(\.notchSize) private var screenNotchSize
    @Environment(\.dynamicNotchState) private var envNookState
    // This screen's window geometry; the widget settings are observed so the open width follows
    // the widget set and sizes.
    @Environment(\.notchWindowGeometry) private var envGeometry
    @StoredSetting(.nookSettings) private var nookSettings
    #if canImport(FanControlKit)
    @StoredSetting(.fanControlWidgetSettings) private var fanWidgetSettings // its size changes the row width
    #endif
    @State private var fallbackGeometry = NotchWindowGeometry()
    private var geometry: NotchWindowGeometry { envGeometry ?? fallbackGeometry }

    /// Offset applied by the width / height fine-tuning views.
    @State private var fineTuningValue: CGFloat = 0

    private var nookState: DynamicNotchState { envNookState ?? .shared }

    // MARK: Geometry

    /// The notch size, widened while fine-tuning.
    var notchSize: CGSize {
        let screenSize = screenNotchSize
        if fineTuningValue == 0 {
            return screenSize
        }
        return CGSize(
            width: screenSize.width + NotchViewFlags.widgetWidth * 0.5,
            height: screenSize.height
        )
    }

    /// Size of the open notch: exactly as wide as the widget row (Σ widget widths + separators +
    /// padding; at least the notch, at most `maxOpenWidth` — wider rows scroll inside).
    var expectedOpenFootprint: CGSize {
        let sz = notchSize
        // minimum width: the notch, or 32 pt for a pseudo notch (≤ 21.12 pt tall)
        let width: CGFloat = (sz.height <= 21.12) ? 32.0 : sz.width
        #if canImport(FanControlKit)
        _ = fanWidgetSettings // observed: the Fan Control widget's size is part of the row width
        #endif
        let clamped = NookWidgetLayout.openWidth(NookWidgetPager.shared.visibleWidgets(nookSettings), // F9: current page
                                                 separatorSpacing: nookSettings.separatorSpacing,
                                                 maxWidth: geometry.maxOpenWidth)
        return CGSize(
            width: max(width, clamped),
            // the widget row keeps its full height below the notch: a taller notch (built-in display
            // at a "More Space" scaling: 64 pt) would otherwise clip the widgets' bottoms
            height: max(sz.height + NookWidgetLayout.rowHeight, 250.0)
        )
    }

    /// Extra width of the closed notch: the live activity's sides (ClosedNotchActivityLayout),
    /// or 70 pt for quick peeks.
    var closedNotchFootprint: CGSize {
        let activeCount = ActiveLiveActivitiesManager.shared.activeLiveActivities.count
        if activeCount == 0 && !CaptureClosedNotchIndicator.isShown // Capture widget: recording indicator
            && !DownloadsClosedNotchIndicator.isShown { // F8: Downloads widget progress indicator
            let quickPeeks = nookState.quickPeeks
            if quickPeeks == nil || quickPeeks!.isEmpty {
                return CGSize(width: 0, height: notchSize.height)
            }
            return CGSize(width: 70.0, height: notchSize.height)
        }
        return CGSize(width: 2 * ClosedNotchActivityLayout.sideWidth(notchSize: notchSize), height: notchSize.height)
    }

    /// Footprint while scrubbing: interpolated between the closed and the open footprint, plus
    /// the overshoot (nil when not scrubbing).
    var scrubFrame: CGSize? {
        let delta = overshootDelta
        guard let scrubValue = viewModel.scrubExpansion else {
            return nil
        }
        let openFP = expectedOpenFootprint
        let closedFP = CGSize(width: notchSize.width + closedNotchFootprint.width,
                              height: closedNotchFootprint.height)
        let indicator: CGFloat = 0.15

        let t = (scrubValue - indicator) / (1.0 - indicator)
        let clampedT = min(max(t, 0), 1.0)

        let interpWidth = closedFP.width + (openFP.width - closedFP.width) * clampedT
        let interpHeight = closedFP.height + (openFP.height - closedFP.height) * clampedT

        let resultWidth = max(interpWidth + delta.width, notchSize.width - 10.0)
        let resultHeight = max(interpHeight + delta.height, notchSize.height)
        return CGSize(width: resultWidth, height: resultHeight)
    }

    /// Liquid-glass hover bloom of the closed notch (nil unless liquid glass is on).
    var beadCatchBand: (size: CGSize, pose: CGFloat)? {
        guard NotchViewFlags.liquidGlass else { return nil }
        let state = nookState
        guard state.mode == .closed else { return nil }

        let notchSz = notchSize
        let openValue: CGFloat
        if viewModel.hovering {
            openValue = 0.1
        } else if let qp = state.quickPeeks, !qp.isEmpty {
            openValue = 0.15
        } else if !ActiveLiveActivitiesManager.shared.activeLiveActivities.isEmpty {
            openValue = 0.15
        } else {
            return nil
        }

        let hoverValue = viewModel.panRawPadding.bottom
        let clampedHover = max(0, min(67.0, hoverValue))
        let bottomBloom = Self.bloomLerp(hover: openValue, open: clampedHover)
        guard bottomBloom > 0 else { return nil }

        let sideBloom = Self.bloomLerp(hover: openValue, open: max(0, 256 - bottomBloom))
        return (size: CGSize(width: sideBloom + notchSz.width, height: notchSz.height), pose: 0)
    }

    // linear stand-in for the liquid-glass bloom curve
    private static func bloomLerp(hover: CGFloat, open: CGFloat) -> CGFloat {
        return hover * open
    }

    /// Rubber-band overshoot of the scrub: exponential in the drag velocity, plus the sideways
    /// growth.
    var overshootDelta: CGSize {
        let velocity = viewModel.scrubOvershoot
        let base: CGFloat
        let rate: CGFloat
        if velocity <= 0 {
            base = -10.0
            rate = 0.22
        } else {
            base = 44.0
            rate = -0.16
        }
        let expResult = exp(velocity / rate)
        let result = (1.0 - expResult) * base
        let lg = lateralGrow
        return CGSize(width: lg + result * 0.35, height: result * 0.35)
    }

    /// Sideways offset while scrubbing, towards the drag.
    var scrubLateralOffset: CGFloat {
        let velocity = viewModel.scrubLateral
        let sign: CGFloat = velocity < 0 ? -1.0 : 1.0
        return lateralGrow * sign * 0.5
    }

    var standardPadding: EdgeInsets {
        return EdgeInsets(top: 1.0, leading: 1.0, bottom: 1.0, trailing: 1.0)
    }

    /// Horizontal scale of the closed notch: hover pop, squashed by the pan (identity when open).
    var actualScaleX: Double {
        if nookState.mode != .closed { return 1.0 }
        if !viewModel.animatingBack {
            let result = viewModel.panPadding.top * 0.02
            let sign: Double = result <= 0 ? 1.0 : -1.0
            return hoverPop - (result + viewModel.scaleDown) * sign
        }
        return hoverPop
    }

    /// Vertical scale: hover pop, squashed by the pan (3× closed, 6× open).
    var actualScaleY: Double {
        if !viewModel.animatingBack {
            var result = viewModel.panPadding.top * 0.0075
            result += viewModel.scaleDown
            let multiplier: Double = nookState.mode == .closed ? 3.0 : 6.0
            let sign: Double = result <= 0 ? 1.0 : -1.0
            return hoverPop - result * sign * multiplier
        }
        return hoverPop
    }

    /// The Nook (widgets) is shown: open on the Nook, or scrubbing the closed notch.
    var showNook: Bool {
        switch nookState.mode {
        case .tray, .dragging: return false
        case .nook: return true
        case .closed: return viewModel.scrubExpansion != nil
        }
    }

    /// The closed notch "pops" (×1.25) while hovered, unless pressed or animating back.
    var hoverPop: Double {
        if nookState.quickPeeks == nil,
           viewModel.hovering,
           !viewModel.pressing,
           nookState.mode == .closed,
           !viewModel.animatingBack {
            return 1.25
        }
        return 1.0
    }

    /// Sideways growth while scrubbing (saturates at 28 pt).
    var lateralGrow: CGFloat {
        let velocity = viewModel.scrubLateral
        if velocity != 0 {
            return (1.0 - exp(abs(velocity) / -90.0)) * 28.0
        }
        return 0
    }

    /// A fullscreen app is frontmost: the notch closes and stays closed.
    var isDisabledDueToFullScreen: Bool {
        if NotchViewFlags.disabled { return false }
        return FullscreenMonitor.shared.isFullScreen
    }

    var shouldShowIndicator: Bool {
        guard nookState.indicator != nil else { return false }
        return NSScreen.main != nil
    }

    /// Smoothstep of the open progress (the scrub expansion, else 0 closed / 1 open) between
    /// `start` and `end`.
    func openReveal(_ start: CGFloat, _ end: CGFloat) -> Double {
        let value: Double
        if let scrubValue = viewModel.scrubExpansion {
            value = Double(scrubValue)
        } else {
            value = (nookState.mode == .closed) ? 0.0 : 1.0
        }
        var t = (value - Double(start)) / (Double(end) - Double(start))
        if t <= 0 { t = 0 }
        if t > 1 { t = 1 }
        return (3.0 - 2.0 * t) * t * t
    }

    /// The footprint the notch currently occupies.
    private var currentFootprint: CGSize {
        if viewModel.showIntro { return expectedOpenFootprint } // the intro card is open-sized
        if let frame = scrubFrame { return frame }
        if nookState.mode == .closed {
            return CGSize(width: notchSize.width + closedNotchFootprint.width,
                          height: closedNotchFootprint.height)
        }
        return expectedOpenFootprint
    }

    // MARK: - Body

    // Layout of the open/close animation:
    //   - the whole notch is drawn in a FIXED canvas (the notch window's size), hung from the top;
    //   - the content (top row + nook/tray) has a fixed frame (the open footprint) and is masked by
    //     the same animatable NotchShape that draws the black background, so every element —
    //     including Canvas-drawn charts — is clipped by, and moves with, the notch;
    //   - only `footprint` (an animatable shape size) and the reveal (opacity/scale) animate, with
    //     one spring per direction (AnimationsModifier); the widget grid is not rebuilt or
    //     re-laid-out during the animation.
    var cornerRadius: CGFloat {
        (nookState.mode == .closed && viewModel.scrubExpansion == nil && !viewModel.showIntro) ? 10 : 24
    }

    /// Intro / indicator / (top row + nook or tray), at fixed sizes (see the layout notes above).
    @ViewBuilder
    private func notchContent(footprint: CGSize, reveal: Double, openFootprint: CGSize,
                              isOpen: Bool, mountContent: Bool) -> some View {
        Group {
            if viewModel.showIntro {
                IntroView()
                    .frame(width: openFootprint.width, height: openFootprint.height)
            } else if shouldShowIndicator {
                IndicatorView()
            } else {
                VStack(alignment: .center, spacing: 0) {
                    // top row (notch height): closed → live activities beside the camera housing;
                    // open → the top bar (tabs / actions)
                    ZStack {
                        if isOpen {
                            TopBarView()
                                .opacity(reveal)
                                .transition(.opacity)
                        } else {
                            ClosedNotchActivitiesView(notchSize: notchSize)
                                .transition(.opacity)
                        }
                    }
                    .frame(width: max(footprint.width, notchSize.width), height: notchSize.height)
                    if mountContent {
                        Group {
                            if nookState.mode == .tray || nookState.mode == .dragging {
                                TrayView()
                            } else {
                                NookView()
                            }
                        }
                        // fixed size: the grid is laid out once at the open size, never per frame
                        .environment(\.nookRowAvailableWidth, openFootprint.width)
                        .frame(width: openFootprint.width,
                               height: max(openFootprint.height - notchSize.height, 0),
                               alignment: .top)
                        // reveal: small blur (re-rendered every frame) and scale; hit testing only when open
                        .blur(radius: (1.0 - reveal) * 4.0)
                        .scaleEffect(0.94 + 0.06 * reveal, anchor: .top)
                        .opacity(reveal)
                        .allowsHitTesting(nookState.mode != .closed)
                        .transition(.opacity)
                    }
                }
                .padding(standardPadding)
            }
        }
    }

    var body: some View {
        #if DEBUG
        let _ = DebugHooks.notchBodyCount += 1
        #endif
        let footprint = currentFootprint
        let reveal = openReveal(0.3, 1.0)
        let openFootprint = expectedOpenFootprint
        let canvas = geometry.canvas
        let isOpen = nookState.mode != .closed || viewModel.scrubExpansion != nil

        notchContent(footprint: footprint, reveal: reveal, openFootprint: openFootprint,
                     isOpen: isOpen, mountContent: isOpen)
        // Rectangular clip to the animated footprint: AppKit-backed views inside widgets
        //   (NSViewRepresentable: calendar day scroller, popup-button menus, text fields) ignore
        //   SwiftUI masks/opacity but honour a clipping frame. The child keeps its fixed size, so
        //   this does not re-lay-out the content.
        .frame(width: max(footprint.width, 1), height: max(footprint.height, 1), alignment: .top)
        .clipped()
        .frame(width: canvas.width, height: canvas.height, alignment: .top)
        // clip everything to the (animated) notch shape (rounded corners)
        .mask(alignment: .top) {
            NotchShape(notchWidth: footprint.width, notchHeight: footprint.height, cornerRadius: cornerRadius)
                .frame(width: canvas.width, height: canvas.height)
        }
        .coordinateSpace(name: "drop-zone")
        .modifier(ShapeModifier(viewModel: viewModel, state: nookState, footprint: footprint, cornerRadius: cornerRadius, canvas: canvas))
        #if canImport(FanControlKit) // fan-control-integration.md (b-2): pause fan polling while the Nook is hidden
        .onChange(of: nookState.mode, initial: true) { _, _ in
            // per-screen states: the Nook is visible while any screen shows it; idempotent
            FanControlNookVisibility.nookVisibilityChanged(isVisible: DynamicNotchState.anyScreen(in: .nook))
        }
        #endif
        // refit this screen's window when the open width changes (widget set / sizes); not per frame
        .onChange(of: openFootprint, initial: true) { _, size in
            viewModel.openFootprintSize = size
            geometry.fit(openWidth: max(size.width, NookWidgetLayout.windowOpenWidth(nookSettings, maxWidth: geometry.maxOpenWidth))) // F9: widest page
        }
        .offset(x: scrubLateralOffset)
        .scaleEffect(x: actualScaleX, y: actualScaleY, anchor: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .modifier(LockedIndicatorModifier(state: nookState))
        .modifier(AnimationsModifier(state: nookState, hovering: viewModel.hovering))
        .modifier(GesturesModifier(viewModel: viewModel, state: nookState))
        .modifier(EnvironmentsModifier(viewModel: viewModel, state: nookState, notchSize: notchSize))
        .modifier(SideEffectsModifier())
        .onChange(of: FullscreenMonitor.shared.fullScreenStateDict, initial: false) { _, _ in
            viewModel.update(settings: GeneralSettings.defaultValue,
                             isNonNotch: NotchViewFlags.isNonNotch,
                             isFullScreen: isDisabledDueToFullScreen)
        }
        .onChange(of: isDisabledDueToFullScreen, initial: false) { _, disabled in
            // close the notch while a fullscreen app is frontmost
            if disabled && nookState.mode != .closed {
                withAnimation(.notchClose) {
                    nookState.mode = .closed
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 1.0, blendDuration: 0), value: nonNotchHeight)
        .task {
            viewModel.update(settings: GeneralSettings.defaultValue,
                             isNonNotch: NotchViewFlags.isNonNotch,
                             isFullScreen: isDisabledDueToFullScreen)
        }
    }

    private var nonNotchHeight: CGFloat {
        if isDisabledDueToFullScreen {
            return 0
        }
        if NotchViewFlags.isNonNotch || NotchViewFlags.isNonNotchAndDisabled {
            return 0
        }
        return 0.5
    }
}

// MARK: - NotchView.ShapeModifier

extension NotchView {
    struct ShapeModifier: ViewModifier {
        let viewModel: NotchViewModel
        let state: DynamicNotchState
        var footprint: CGSize = .zero
        var cornerRadius: CGFloat = 10
        var canvas: CGSize = .zero

        // DEBUG `animperf`: probe the shape on the screen with a hardware notch only
        @Environment(\.notchSize) private var screenNotchSize

        /// The black background is drawn: always when open; when closed only while something is
        /// shown or happening (hover, press, scrub, indicator, quick peek, live activity, recording).
        var shouldRender: Bool {
            let activities = ActiveLiveActivitiesManager.shared.activeLiveActivities
            if state.mode == .closed {
                return viewModel.hovering
                    || viewModel.pressing
                    || viewModel.scrubExpansion != nil
                    || state.indicator != nil
                    || !(state.quickPeeks ?? []).isEmpty
                    || !activities.isEmpty
                    || CaptureClosedNotchIndicator.isShown // Capture widget: recording indicator
                    || DownloadsClosedNotchIndicator.isShown // F8: Downloads widget progress indicator
            }
            return true
        }

        // Background: the same animatable NotchShape (and the same fixed canvas) as NotchView's
        // content mask, so background and content can never drift; NotchGesturer receives hover
        // (`.onContinuousHover` → NotchViewModel.setPointerOver, NotchHover.swift), drops and the
        // hover-frame reader reports the notch's screen frame.
        func body(content: Content) -> some View {
            content
                .background(alignment: .top) {
                    ZStack(alignment: .top) {
                        // Always in the hierarchy so its size keeps interpolating; when it should not
                        // render (closed, idle) it is hidden only after the close spring has
                        // settled (it is then notch-sized, behind the camera housing).
                        NotchShape(notchWidth: footprint.width,
                                   notchHeight: footprint.height,
                                   cornerRadius: cornerRadius,
                                   probe: screenNotchSize.height > 30)
                            .frame(width: canvas.width, height: canvas.height)
                            // idle: not fully transparent, so the window server still routes
                            // hover / clicks / drags in the closed footprint to this window
                            // (fully transparent pixels of a non-opaque window are click-through)
                            .opacity(shouldRender ? 1 : 0.012)
                            .animation(shouldRender ? nil : .linear(duration: 0.08).delay(0.5), value: shouldRender)
                        NotchGesturer()
                            .frame(width: footprint.width, height: footprint.height)
                            .onContinuousHover(coordinateSpace: .local) { phase in
                                switch phase {
                                case .active: viewModel.setPointerOver(notch: true, band: nil)
                                case .ended: viewModel.setPointerOver(notch: false, band: nil)
                                }
                            }
                            .modifier(NotchDropModifier(viewModel: viewModel))
                        NotchHoverFrameReader(report: { rect in
                            // only store real changes (the reader reports on every frame of a resize)
                            if viewModel.hoverScreenFrame != rect { viewModel.hoverScreenFrame = rect }
                        })
                        .frame(width: footprint.width, height: footprint.height)
                        .allowsHitTesting(false)
                    }
                    .frame(width: canvas.width, height: canvas.height, alignment: .top)
                }
        }
    }
}

// MARK: - NotchView.GesturesModifier

extension NotchView {
    struct GesturesModifier: ViewModifier {
        let viewModel: NotchViewModel
        let state: DynamicNotchState

        /// Resting expansion of the closed notch when a scrub starts (0.15 while something is shown).
        var scrubResolveFloor: CGFloat {
            let quickPeeks = state.quickPeeks
            if quickPeeks == nil || quickPeeks!.isEmpty {
                if ActiveLiveActivitiesManager.shared.activeLiveActivities.isEmpty {
                    return 0
                }
            }
            return 0.15
        }

        /// Reacts to a hover change (the hover state machine in NotchHover.swift): hover-in on the
        /// closed notch schedules the open, hover-out on the open notch arms the guarded close.
        func applyHover(_ hover: Bool) {
            if state.mode == .dragging {
                // while dragging only the hovering flag is updated
                if !hover { viewModel.hovering = false }
                viewModel.cancelHoverGuard()
                return
            }

            viewModel.glassWarm = hover

            if !hover {
                if NotchViewFlags.liquidGlass && !state.locked && !viewModel.animatingBack {
                    if viewModel.scrubWouldToggle(velocityY: 0) {
                        vibrate()
                        withAnimation(.liquidCloseFootprint) {
                            state.mode = .closed
                        }
                    } else {
                        vibrate()
                        withAnimation(.liquidOpenFootprint) { }
                        if viewModel.cancelPan {
                            viewModel.cancelPan = false
                        }
                    }
                    return
                }
                guard !state.locked else { return }
                guard state.mode != .closed else { viewModel.cancelHoverGuard(); return }
                // close only after the pointer has really left (grace period, hover band below the
                // open notch) and nothing presented from the notch is in use
                let animation: Animation = NotchViewFlags.liquidGlass ? .liquidHoverOut : .notchClose
                let notch = self.state
                viewModel.scheduleGuardedClose {
                    guard !notch.locked, notch.mode == .nook || notch.mode == .tray else { return }
                    withAnimation(animation) { notch.mode = .closed }
                }
            } else if state.mode == .closed {
                // hover-in opens this screen's notch after a short dwell, so sweeping the pointer
                // across the menu bar does not open it
                guard !state.locked, viewModel.scrubExpansion == nil else { return }
                viewModel.scheduleHoverOpen { [self] in
                    if state.mode == .closed { openNotch() }
                }
            } else {
                viewModel.cancelHoverGuard()
            }
        }

        private func openNotch() {
            let animation: Animation = NotchViewFlags.liquidGlass ? .liquidOpenFootprint : .notchOpen
            withAnimation(animation) {
                state.select(DynamicNotchState.preferredOpenMode == .tray ? .tray : .nook)
            }
        }

        func body(content: Content) -> some View {
            content
                .onTapGesture {
                    if state.mode == .closed {
                        vibrate()
                        openNotch()
                    }
                }
                .onLongPressGesture(minimumDuration: 0.15, maximumDistance: 30.0) {
                    if state.mode == .closed {
                        openNotch()
                    }
                } onPressingChanged: { pressing in
                    viewModel.pressing = pressing
                }
                .onChange(of: viewModel.hovering) { _, hovering in
                    applyHover(hovering)
                }
                .onChange(of: state.mode) { old, new in
                    viewModel.endScrub()
                    // after a drop the notch is in the tray, but no hover-out will come (drag sessions
                    // do not report hover): arm the guarded close so it closes once the pointer is away
                    if old == .dragging, new == .tray, !viewModel.hovering { applyHover(false) }
                    if new == .closed { viewModel.cancelHoverGuard() }
                }
        }
    }
}

// MARK: - NotchView.AnimationsModifier

extension NotchView {
    struct AnimationsModifier: ViewModifier {
        let state: DynamicNotchState
        var hovering: Bool = false

        // One spring per direction for every mode change, whatever started it (tap, hover-out,
        // debug hook, drag): this `.animation(_:value:)` overrides the transaction of the various
        // `withAnimation` call sites, so an under-damped spring can never overshoot the closed size
        // (the notch would shoot up past the top of the screen and bounce back).
        func body(content: Content) -> some View {
            content
                .animation(state.mode == .closed ? .notchClose : .notchOpen, value: state.mode)
                .animation(.notchHover, value: hovering)
                .animation(.indicatorResize, value: state.indicator)
                .animation(.smooth, value: ActiveLiveActivitiesManager.shared.activeLiveActivities.count)
        }
    }
}

// MARK: - NotchView.SideEffectsModifier

extension NotchView {
    struct SideEffectsModifier: ViewModifier {
        func handleChange(for kind: Indicator.Kind) async {
            do {
                let value = try await getValue(for: kind)
                withAnimation(.indicatorResize) {
                    updateIndicator(kind: kind, value: value)
                }
                try await Task.sleep(nanoseconds: 50_000_000)
            } catch {
                print("Error handling change: \(error.localizedDescription)")
            }
        }

        private func getValue(for kind: Indicator.Kind) async throws -> CGFloat {
            return 0
        }

        private func updateIndicator(kind: Indicator.Kind, value: CGFloat) {
        }

        // remembers the last launched version (for a changelog)
        func handleChangelog() {
            let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            let lastVersion = UserDefaults.standard.string(forKey: "lastVersionNumber") ?? ""
            if shouldShowChangelog(lastVersion: lastVersion, currentVersion: currentVersion) {
                UserDefaults.standard.set(currentVersion, forKey: "lastVersionNumber")
            }
        }

        private func shouldShowChangelog(lastVersion: String, currentVersion: String) -> Bool {
            return lastVersion != currentVersion
        }

        func body(content: Content) -> some View {
            content
                .onAppear {
                    handleChangelog()
                }
        }
    }
}

// MARK: - NotchView.EnvironmentsModifier

extension NotchView {
    struct EnvironmentsModifier: ViewModifier {
        let viewModel: NotchViewModel
        let state: DynamicNotchState
        var notchSize: CGSize = .zero

        var nookWidgetsWidth: NookGrid.Point {
            NookSettings.defaultValue.widgetsWidth
        }

        func openNotch(in mode: DynamicNotchState.NotchMode) {
            let animation: Animation = NotchViewFlags.liquidGlass ? .liquidOpenFootprint : .defaultTransition
            withAnimation(animation) {
                state.select(mode)
            } completion: {
                viewModel.animatingBack = false
            }
        }

        func closeNotch(vibrate shouldVibrate: Bool, unhover: Bool) {
            let animation: Animation
            if NotchViewFlags.liquidGlass {
                animation = unhover ? .liquidHoverOut : .liquidCloseFootprint
            } else {
                animation = .notchClose
            }
            if shouldVibrate { vibrate() }
            if viewModel.cancelPan { viewModel.cancelPan = false }
            withAnimation(animation) {
                state.mode = .closed
                if unhover { viewModel.hovering = false }
            }
        }

        func body(content: Content) -> some View {
            content
                .environment(\.dynamicNotchState, state)
                .environment(\.notchViewModel, viewModel)
                .environment(\.notchMode, state.mode)
                .environment(\.notchSize, notchSize)
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - NotchView.LockedIndicatorModifier

extension NotchView {
    struct LockedIndicatorModifier: ViewModifier {
        let state: DynamicNotchState

        func body(content: Content) -> some View {
            content
                .overlay(alignment: .top) {
                    if state.locked {
                        LockedIndicatorView()
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                }
        }
    }
}

// MARK: - Notch open/close springs

extension Animation {
    // Critically damped close (no overshoot past the closed size), a lightly under-damped open,
    // and a quick, fully damped hover pop.
    static var notchOpen: Animation { .spring(response: 0.42, dampingFraction: 0.82, blendDuration: 0) }
    static var notchClose: Animation { .spring(response: 0.36, dampingFraction: 1.0, blendDuration: 0) }
    static var notchHover: Animation { .spring(response: 0.28, dampingFraction: 1.0, blendDuration: 0) }
}
