import AppKit
import SwiftUI
import Observation

/// Interaction state of one screen's notch: hover (NotchHover.swift), press, scrub (the
/// interactive open/close drag), pan stretch and drop targets. Created per screen by RootView;
/// `shared` is the fallback for views outside a notch window.
@Observable
final class NotchViewModel {
    static let shared = NotchViewModel()

    // MARK: - Observed state

    /// Pointer location of a drag over the notch, and the drop targets' frames (`hoveredDropTargetID`).
    var droppingCoords: CGPoint? = nil
    var availableActions: [Pipeline] = []
    var targetsCoords: [String: CGRect] = [:]

    var pressing: Bool = false
    /// The pointer is over the notch (or its hover band); drives the hover state machine.
    var hovering: Bool = false
    var cancelPan: Bool = false
    /// Raw pan offsets; `panPadding` maps them to a rubber-band stretch.
    var panRawPadding: EdgeInsets = EdgeInsets()
    var panGestureCounter: Int = 0
    var glassWarm: Bool = false

    /// Scrub (interactive open/close): expansion 0 (closed) … 1 (open), nil when not scrubbing.
    var scrubExpansion: CGFloat? = nil
    var scrubOvershoot: CGFloat = 0
    var scrubLateral: CGFloat = 0
    var scrubClosing: Bool = false

    /// `.full` until `update(settings:isNonNotch:isFullScreen:)` decides otherwise.
    var notchState: NotchState = NotchState(unsafeTag: 4)
    var scaleDown: Double = 0
    var animatingBack: Bool = false
    var showIntro: Bool = false

    // MARK: - Unobserved state
    // Written often (hoverScreenFrame on every frame of a resize, the pointer flags on every mouse
    // move); observing them would re-evaluate the notch for nothing.

    @ObservationIgnored var isPanning: Bool = false
    /// Hover inputs, reconciled into `hovering` by `setPointerOver(notch:band:)`.
    @ObservationIgnored var pointerOverNotch: Bool = false
    @ObservationIgnored var pointerOverBand: Bool = false
    @ObservationIgnored var hoverUnionActive: Bool = false
    @ObservationIgnored var hoverReconcileScheduled: Bool = false
    @ObservationIgnored var applyHover: (notch: Bool, band: Bool)? = nil
    /// The notch's frame in screen coordinates (NotchHoverFrameReader).
    @ObservationIgnored var hoverScreenFrame: CGRect = .zero

    // Top-bar tab hover handoff (`beginTabHoverHandoff()`).
    @ObservationIgnored var tabHoverFrameChangedAt: Double = 0
    @ObservationIgnored var tabHoverStartedAt: Double = 0
    @ObservationIgnored var tabHoverPressPoint: CGPoint = .zero
    @ObservationIgnored var tabHoverOrigin: CGRect = .zero
    @ObservationIgnored var tabHoverHandoffInactive: Bool = true
    @ObservationIgnored var tabHoverTimer: Timer? = nil

    // Per-screen wiring and the hover open/close state machine (NotchHover.swift).
    @ObservationIgnored weak var screenNotchState: DynamicNotchState?
    @ObservationIgnored weak var notchWindow: NSWindow?
    /// Size of the open notch (set by NotchView when it changes); the close guard's hover band is
    /// built around it.
    @ObservationIgnored var openFootprintSize: CGSize = .zero
    /// Pending hover-open (the dwell before the notch opens).
    @ObservationIgnored var hoverOpenTask: Task<Void, Never>? = nil
    /// Close guard (polls while a hover-out close is pending).
    @ObservationIgnored var hoverGuardTimer: Timer? = nil
    @ObservationIgnored var hoverGuardOutsideSince: TimeInterval? = nil

    // Scrub bookkeeping.
    @ObservationIgnored var scrubFloor: CGFloat = 0
    @ObservationIgnored var scrubRaw: CGFloat = 0
    @ObservationIgnored var scrubPastThreshold: Bool = false
    @ObservationIgnored var scrubCommitting: Bool = false
    @ObservationIgnored var scrubCommitToken: Int = 0

    // MARK: - Derived values

    /// The drop target under the dragged item.
    var hoveredDropTargetID: String? {
        guard let coords = droppingCoords else { return nil }

        for (key, rect) in targetsCoords {
            if rect.contains(coords) {
                return key
            }
        }
        return nil
    }

    /// Rubber-band stretch for the raw pan offsets (at most 32 pt per edge; 150 pt of travel, 200 on
    /// the trailing edge).
    var panPadding: EdgeInsets {
        let raw = panRawPadding

        let top    = interpolateEdge(raw.top,    max: 150, springback: 32)
        let leading = interpolateEdge(raw.leading, max: 150, springback: 32)
        let bottom  = interpolateEdge(raw.bottom,  max: 150, springback: 32)
        let trailing = interpolateEdge(raw.trailing, max: 200, springback: 32)

        return EdgeInsets(top: top, leading: leading, bottom: bottom, trailing: trailing)
    }

    /// `panPadding` for the horizontal edges only.
    var horizontalPanPadding: EdgeInsets {
        let raw = panRawPadding

        let leading  = interpolateEdge(raw.leading,  max: 150, springback: 32)
        let trailing = interpolateEdge(raw.trailing, max: 150, springback: 32)

        return EdgeInsets(top: 0, leading: leading, bottom: 0, trailing: trailing)
    }

    /// Maps a raw offset to its stretch: linear up to `max`, easing back towards 0 past it and
    /// below 0.
    private func interpolateEdge(_ value: CGFloat, max maxValue: CGFloat, springback: CGFloat) -> CGFloat {
        if value < 0 {
            let t = (value / maxValue) * -0.25 + 1.0
            let clamped = max(0, t)
            return springback - clamped * springback
        } else if value <= maxValue {
            let curve = UnitCurve.linear
            let t = curve.value(at: value / maxValue)
            let result = t * springback
            return max(0, min(springback, result))
        } else {
            let normalized = value / maxValue
            let t = (normalized - 1.0) * -0.25 + 1.0
            let clamped = max(0, t)
            return clamped * springback
        }
    }

    init() {}

    // MARK: - Hover

    /// Haptic tick when the pointer leaves the notch.
    private func hoveringWillSet(_ newValue: Bool) {
        if hovering && !newValue {
            if InMemoryGeneralSettings.hapticEnabled {
                let performer = NSHapticFeedbackManager.defaultPerformer
                performer.perform(.generic, performanceTime: .now)

            }
        }
    }

    /// Starts tracking a top-bar tab hover: while the pointer stays within the tab and the notch
    /// frame, a 0.15 s timer keeps the handoff alive (`tabHoverPresence()`).
    func beginTabHoverHandoff() {
        cancelTabHoverHandoff()

        tabHoverTimer?.invalidate()
        tabHoverTimer = nil

        let mouseLoc = NSEvent.mouseLocation

        if hoverScreenFrame.contains(mouseLoc) {
            tabHoverPressPoint = mouseLoc
            tabHoverHandoffInactive = false
            tabHoverStartedAt = ProcessInfo.processInfo.systemUptime

            tabHoverTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
                _ = self?.tabHoverPresence()
            }
        }
    }

    /// Timer callback of the tab hover handoff; false (and cancelled) once the pointer left.
    private func tabHoverPresence() -> Bool {
        if tabHoverHandoffInactive { return false }

        let mouseLoc = NSEvent.mouseLocation

        guard tabHoverOrigin.contains(mouseLoc) else {
            cancelTabHoverHandoff()
            return false
        }

        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = max(now - tabHoverStartedAt, tabHoverFrameChangedAt)

        if elapsed < 0.5 { return true }

        let dx = mouseLoc.x - tabHoverPressPoint.x
        let dy = mouseLoc.y - tabHoverPressPoint.y
        let distance = hypot(dx, dy)

        if distance >= 2.0 && hoverReconcileScheduled {
            if hoverScreenFrame != tabHoverOrigin {
                if tabHoverOrigin.contains(mouseLoc) {
                    cancelTabHoverHandoff()
                }
            }
        }
        return true
    }

    /// Resets handoff state. Called from tabHoverPresence and beginTabHoverHandoff.
    private func cancelTabHoverHandoff() {
        tabHoverOrigin = .zero
        tabHoverHandoffInactive = true
        tabHoverTimer?.invalidate()
        tabHoverTimer = nil
    }

    /// Records the hover inputs and reconciles `hovering` once per main-queue turn (the hover
    /// reports arrive on every mouse move; `hovering` is written only when it changes).
    func setPointerOver(notch: Bool?, band: Bool?) {
        if let notch = notch { pointerOverNotch = notch }
        if let band = band   { pointerOverBand = band }

        guard !hoverReconcileScheduled else { return }

        hoverReconcileScheduled = true

        DispatchQueue.main.async {
            let hovering = self.pointerOverNotch || self.pointerOverBand
            if self.hovering != hovering {
                self.hoveringWillSet(hovering)
                self.hovering = hovering
            }
            self.hoverReconcileScheduled = false
        }
    }

    // MARK: - Scrub

    /// Whether releasing now (with `velocityY`) would flip the notch: fast flicks decide by
    /// direction, slower ones by the projected position against the midpoint.
    func scrubWouldToggle(velocityY: CGFloat) -> Bool {
        guard let expansion = scrubExpansion else { return false }

        if velocityY > 500  { return !scrubClosing }
        if velocityY < -500 { return scrubClosing }

        let projected = expansion + ((velocityY * (1.0 - scrubFloor)) / 300.0) * 0.13

        let midpoint = (scrubFloor + 1.0) / 2.0

        if scrubClosing {
            return projected < midpoint
        } else {
            return midpoint < projected
        }
    }

    /// Starts a scrub from `floor` (closed resting expansion), opening or closing.
    func beginScrub(floor: CGFloat, closing: Bool) {
        if scrubCommitting {
            scrubCommitting = false
            scrubCommitToken += 1
            scrubFloor = floor
            scrubClosing = closing
            scrubPastThreshold = false

            if scrubExpansion == nil {
                scrubRaw = closing ? 1.0 : 0
            } else {
                scrubRaw = scrubExpansion!
            }
            scrubOvershoot = 0
        } else {
            if scrubExpansion == nil {
                scrubFloor = floor
                scrubClosing = closing
                scrubPastThreshold = false
                scrubRaw = closing ? 1.0 : 0
                scrubOvershoot = 0
                scrubLateral = 0

                withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 1.0, blendDuration: 0.25)) {
                }
            }
        }
    }

    /// Commits the scrub at `to`; a new scrub within 0.75 s continues from there.
    func commitScrub(to: CGFloat) {
        scrubCommitting = true
        let token = scrubCommitToken + 1
        scrubCommitToken = token

        scrubExpansion = to
        scrubRaw = to

        scrubOvershoot = 0
        scrubLateral = 0

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            if self.scrubCommitToken == token {
                self.scrubCommitting = false
            }
        }
    }

    /// Moves the scrub by `delta` points (haptic tick when it crosses the midpoint).
    func scrub(by delta: CGFloat) {
        guard scrubExpansion != nil else { return }

        let baseFloor = scrubFloor
        let candidate = baseFloor - 0.25
        let adjusted = delta * ((1.0 - baseFloor) / 300.0)
        var newValue = candidate + adjusted

        newValue = max(candidate, newValue)

        if newValue > 1.35 { newValue = 1.35 }

        newValue = max(baseFloor, newValue)

        if newValue > 1.0 { newValue = 1.0 }

        scrubRaw = newValue

        withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.58, blendDuration: 0.25)) {
        }

        let midpoint = (scrubFloor + 1.0) / 2.0

        let crossed: Bool
        if scrubClosing {
            crossed = midpoint < newValue
        } else {
            crossed = newValue < midpoint
        }

        if crossed != scrubPastThreshold {
            scrubPastThreshold = crossed

            if InMemoryGeneralSettings.hapticEnabled {
                let performer = NSHapticFeedbackManager.defaultPerformer
                performer.perform(.generic, performanceTime: .now)
            }
        }
    }

    /// Ends the scrub. Writes are change-only: this runs on every mode change, and unconditional
    /// writes would re-evaluate NotchView at the start of each open/close animation.
    func endScrub() {
        if scrubExpansion != nil { scrubExpansion = nil }

        if scrubClosing { scrubClosing = false }

        scrubPastThreshold = false
        scrubRaw = 0

        if scrubOvershoot != 0 { scrubOvershoot = 0 }
        if scrubLateral != 0 { scrubLateral = 0 }
    }

    /// Sideways stretch while scrubbing, clamped to ±270.
    func stretchLateral(by: CGFloat, pose: CGFloat) {
        let current = scrubLateral
        var newLateral = by * pose + current

        if newLateral < -270 { newLateral = -270 }
        if newLateral >  270 { newLateral =  270 }

        if current != newLateral {
            scrubLateral = newLateral
        }
    }

    // MARK: - Settings

    /// `.inline` unless the notch is presented in the menu bar or the screen has no notch (`.full`).
    func update(settings: GeneralSettings, isNonNotch: Bool, isFullScreen: Bool) {
        if !Self.isPresentedInMenuBar(settings) && !isNonNotch {
            guard notchState.tag != 2 else { return }
            notchState = NotchState(unsafeTag: 2)
        } else {
            guard notchState.tag != 4 else { return }
            notchState = NotchState(unsafeTag: 4)
        }
    }
}

// MARK: - NotchState tags

extension NotchState {
    init(unsafeTag: UInt8) {
        switch unsafeTag {
        case 0: self = .hidden
        case 1: self = .nook
        case 2: self = .inline
        case 3: self = .locked
        case 4: self = .full
        default: self = .full
        }
    }

    var tag: UInt8 {
        switch self {
        case .hidden: return 0
        case .nook:   return 1
        case .inline: return 2
        case .locked: return 3
        case .full:   return 4
        }
    }
}

/// Haptic feedback setting (General settings).
private enum InMemoryGeneralSettings {
    static var hapticEnabled: Bool {
        GeneralSettings.defaultValue.hapticFeedbackEnabled
    }
}

extension NotchViewModel {
    /// "Present the notch in the menu bar" — not a General setting (yet), so always off.
    fileprivate static func isPresentedInMenuBar(_ settings: GeneralSettings) -> Bool {
        return false
    }
}
