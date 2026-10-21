// Hover open/close of the per-screen notch windows.
//
// Every screen has its own NotchViewModel and DynamicNotchState, so only the notch under the
// pointer reacts. The hover input travels:
//
//   NotchGesturer .onContinuousHover ──▶ NotchViewModel.setPointerOver(notch:band:)
//     (coalesced on the main queue; `hovering` is written only when it changes)
//   ──▶ NotchView.GesturesModifier .onChange(of: hovering) ──▶ applyHover(_:)
//
// and drives this state machine (one hover timer per view model: `cancelHoverGuard()` cancels
// whichever is pending):
//
//                 hover-in                            dwell elapsed (`hoverOpenDelay`),
//                 (not locked / scrubbing /           still hovering, not suppressed
//    ┌────────┐    suppressed) ┌───────────┐ ─────────────────────────────▶ ┌──────────────┐
//    │ closed │ ─────────────▶ │  opening  │                                │ open         │
//    │        │ ◀───────────── │ (one-shot)│     tap / long press ────────▶ │ (nook, tray) │
//    └────────┘   hover-out    └───────────┘     opens at once from closed  └──────────────┘
//        ▲                                                                   │        ▲
//        │                                                         hover-out │        │ hover-in
//        │                                                                   ▼        │ (cancel)
//        │   outside the open notch + band for `closeGrace`,        ┌───────────────────┐
//        └───────────────────────────────────────────────────────── │ closing (20 Hz    │
//            and not busy                                           │ guard poll)       │
//                                                                   └───────────────────┘
//
// - opening: hover-open is suppressed while a timer alert rings in the closed notch (its "Stop"
//   capsule must stay clickable; a click elsewhere on the closed notch still opens it) and while
//   a Capture countdown / screenshot runs (`hoverOpenSuppressed`). It resumes on the next hover-in.
// - closing: the guard keeps resetting its grace period while the pointer is inside the open
//   notch plus a generous band (`bandSide` / `bandBelow`), or while the notch is busy
//   (`notchIsBusy`): an NSMenu is tracking (SwiftUI `Menu`, popup buttons, context menus),
//   a popover / sheet / child window is shown, text is being edited, the left mouse button is held
//   (dragging a tray file out, scrubbing), or a widget declared an interaction
//   (`NotchInteractionMonitor.begin()/end()`). Spurious hover-outs — the pointer crossing the
//   transparent rounded corners, the window becoming key on click, a menu window taking the
//   pointer — therefore do not close the notch.
// - While a drag is over the notch (`.dragging`) hover only updates the flag; after a drop into
//   the tray a hover-out is replayed so the guard closes it once the pointer is away.
import AppKit
import SwiftUI

/// Counts what keeps an open notch from closing on hover-out: tracked menus and explicit widget
/// interactions.
enum NotchInteractionMonitor {
    private(set) static var menuTrackingDepth = 0
    private(set) static var explicitInteractions = 0
    /// The menu being tracked (DEBUG `menutest` dismisses it).
    private(set) static weak var trackingMenu: NSMenu?
    private static var observers: [NSObjectProtocol] = []

    static func install() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        #if DEBUG
        installDebugHoverProbe()
        #endif
        observers.append(center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { note in
            menuTrackingDepth += 1
            trackingMenu = note.object as? NSMenu
        })
        observers.append(center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { _ in
            menuTrackingDepth = max(0, menuTrackingDepth - 1)
        })
    }

    /// Widgets can keep the notch open around a custom interaction (balanced calls).
    static func begin() { explicitInteractions += 1 }
    static func end() { explicitInteractions = max(0, explicitInteractions - 1) }
}

extension NotchViewModel {
    static let hoverOpenDelay: TimeInterval = 0.12
    static let closeGrace: TimeInterval = 0.32
    static let bandSide: CGFloat = 24
    static let bandBelow: CGFloat = 56

    /// Screen rectangle of the open notch plus the hover band (nil before the window exists).
    var openHoverRegion: CGRect? {
        guard let window = notchWindow, openFootprintSize.width > 0 else { return nil }
        let f = window.frame
        let w = openFootprintSize.width, h = openFootprintSize.height
        return CGRect(x: f.midX - w / 2 - Self.bandSide, y: f.maxY - h - Self.bandBelow,
                      width: w + 2 * Self.bandSide, height: h + Self.bandBelow + 1)
    }

    /// Something presented from / happening in the notch that must keep it open.
    var notchIsBusy: Bool {
        if NotchInteractionMonitor.menuTrackingDepth > 0 || NotchInteractionMonitor.explicitInteractions > 0 { return true }
        if NookWidgetPager.shared.isInteracting { return true } // F9: widget drag / page swipe in the open notch
        // a button is held: a drag (e.g. a tray file being dragged out to Finder), a press, a
        // slider/scrubber — close only after release
        if NSEvent.pressedMouseButtons & 1 != 0 { return true }
        guard let window = notchWindow else { return false }
        if window.attachedSheet != nil { return true }
        if (window.childWindows ?? []).contains(where: { $0.isVisible }) { return true }
        if NSApp.windows.contains(where: { $0 !== window && $0.isVisible && $0.parent === window }) { return true }
        if window.isKeyWindow, window.firstResponder is NSText { return true }
        return false
    }

    #if DEBUG
    /// Notch window → its view model (DEBUG hooks `hovertest` / `menutest`).
    static let debugByWindow = NSMapTable<NSWindow, NotchViewModel>.weakToWeakObjects()
    #endif

    /// Cancels a pending hover-open and the close guard.
    func cancelHoverGuard() {
        hoverOpenTask?.cancel()
        hoverOpenTask = nil
        hoverGuardTimer?.invalidate()
        hoverGuardTimer = nil
        hoverGuardOutsideSince = nil
    }

    /// A timer alert is ringing in the closed notch (orange "Stop" capsule shown): hovering must
    /// not open the notch then, or the pointer could never reach Stop. Only the ringing alert
    /// counts — a running/paused timer's compact/minimal activity does not suppress hover-open.
    /// Also suppressed while a Capture countdown/screencapture runs (the notch would be in the shot).
    @MainActor static var hoverOpenSuppressed: Bool {
        (!NookTimersStore.shared.alertingIDs.isEmpty && LiveActivityCenter.shared.currentActivity == .timerExpired)
            || CaptureManager.suppressesNotchHoverOpen
    }

    /// Open after `hoverOpenDelay` if the pointer is still over the closed notch (never while
    /// `hoverOpenSuppressed`). Cancelled by hover-out.
    @MainActor func scheduleHoverOpen(_ open: @escaping () -> Void) {
        cancelHoverGuard()
        if Self.hoverOpenSuppressed { return }
        hoverOpenTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(Self.hoverOpenDelay)) } catch { return }
            // cancelled after the sleep finished but before this resumed: a newer hover owns the slot
            guard let self, !Task.isCancelled else { return }
            self.hoverOpenTask = nil
            if self.hovering, !Self.hoverOpenSuppressed { open() }
        }
    }

    /// Close once the pointer has stayed outside the open notch + band for `closeGrace` and the
    /// notch is not busy (see the file header). Cancelled by hover-in.
    func scheduleGuardedClose(_ close: @escaping () -> Void) {
        cancelHoverGuard()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { t.invalidate(); return }
                if self.hovering { self.cancelHoverGuard(); return }
                let now = ProcessInfo.processInfo.systemUptime
                let inBand = self.openHoverRegion?.contains(NSEvent.mouseLocation) ?? false
                if inBand || self.notchIsBusy {
                    self.hoverGuardOutsideSince = nil
                    return
                }
                let since = self.hoverGuardOutsideSince ?? now
                self.hoverGuardOutsideSince = since
                if now - since >= Self.closeGrace {
                    self.cancelHoverGuard()
                    close()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverGuardTimer = timer
    }
}
