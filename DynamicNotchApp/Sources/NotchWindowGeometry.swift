import AppKit
import SwiftUI

/// Size of one screen's notch window and the widest the open notch may be there.
/// The open notch is exactly as wide as its content (NookWidgetLayout.openWidth); the window is
/// refitted (never during an animation frame: only when that width changes, i.e. when the widget
/// set / sizes change, at the latest when the notch opens) so the canvas always holds the open
/// notch plus the spring's overshoot, centred on the screen's notch and clamped to the screen.
@Observable
final class NotchWindowGeometry {
    /// Room beside the open notch for the open spring's overshoot and the top-corner ears.
    static let sideMargin: CGFloat = 40
    static let height: CGFloat = 360
    /// The open notch never grows wider than this share of the screen; wider rows scroll.
    static let maxScreenShare: CGFloat = 0.8

    var canvas = CGSize(width: 900, height: height)
    var maxOpenWidth: CGFloat = 820
    @ObservationIgnored weak var window: NSWindow?
    @ObservationIgnored var screenFrame: CGRect = .zero
    @ObservationIgnored var horizontalOffset: CGFloat = 0 // DEBUG offscreen instances

    func update(screen: NSScreen) {
        screenFrame = screen.frame
        // never wider than the screen minus the side margins either (a wider row scrolls inside)
        var maxOpen = floor(min(screen.frame.width * Self.maxScreenShare, screen.frame.width - 2 * Self.sideMargin))
        #if DEBUG
        // DN_DEBUG_MAX_OPEN=<pt>: pretend the screen is narrow (tests the scrolling widget row)
        if let v = ProcessInfo.processInfo.environment["DN_DEBUG_MAX_OPEN"].flatMap(Double.init) { maxOpen = min(maxOpen, v) }
        #endif
        if maxOpenWidth != maxOpen { maxOpenWidth = maxOpen }
    }

    func frame(forOpenWidth openWidth: CGFloat) -> NSRect {
        let s = screenFrame
        let w = min(ceil(openWidth) + 2 * Self.sideMargin, s.width)
        return NSRect(x: (s.midX - w / 2).rounded() + horizontalOffset, y: s.maxY - Self.height,
                      width: w, height: Self.height)
    }

    /// Resize the window (and the SwiftUI canvas, without animation) for an open width.
    @MainActor func fit(openWidth: CGFloat) {
        let frame = frame(forOpenWidth: openWidth)
        if let window, window.frame != frame { window.setFrame(frame, display: true) }
        if canvas != frame.size {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { canvas = frame.size }
        }
    }
}

private struct NotchWindowGeometryKey: EnvironmentKey {
    static let defaultValue: NotchWindowGeometry? = nil
}

extension EnvironmentValues {
    var notchWindowGeometry: NotchWindowGeometry? {
        get { self[NotchWindowGeometryKey.self] }
        set { self[NotchWindowGeometryKey.self] = newValue }
    }
}
