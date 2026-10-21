import SwiftUI

/// The notch outline: hung from the top edge of its rect and horizontally centred, with a flat
/// top, small outward "ears" at the top corners (like the hardware notch) and rounded bottom
/// corners. Width, height and corner radius are all animatable, so one animated footprint drives
/// both the black background and the content mask identically (NotchView).
struct NotchShape: Animatable, Shape, View {
    var notchWidth: CGFloat = 320.0
    var notchHeight: CGFloat = 36.0
    /// Radius of the bottom corners.
    var cornerRadius: CGFloat = 14.0

    /// DEBUG measurement only (DebugHooks `animperf`): record this shape's geometry per frame.
    var probe: Bool = false

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(notchWidth, AnimatablePair(notchHeight, cornerRadius)) }
        set {
            notchWidth = newValue.first
            notchHeight = newValue.second.first
            cornerRadius = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let w = max(notchWidth, 0)
        let h = max(notchHeight, 0)
        let r = min(max(cornerRadius, 0), h / 2, w / 2)
        let ear = min(r * 0.5, 8)          // outward top-corner flare
        let x0 = rect.midX - w / 2, x1 = rect.midX + w / 2
        let top = rect.minY, bottom = rect.minY + h
        var p = Path()
        p.move(to: CGPoint(x: x0 - ear, y: top))
        p.addQuadCurve(to: CGPoint(x: x0, y: top + ear), control: CGPoint(x: x0, y: top))
        p.addLine(to: CGPoint(x: x0, y: bottom - r))
        p.addQuadCurve(to: CGPoint(x: x0 + r, y: bottom), control: CGPoint(x: x0, y: bottom))
        p.addLine(to: CGPoint(x: x1 - r, y: bottom))
        p.addQuadCurve(to: CGPoint(x: x1, y: bottom - r), control: CGPoint(x: x1, y: bottom))
        p.addLine(to: CGPoint(x: x1, y: top + ear))
        p.addQuadCurve(to: CGPoint(x: x1 + ear, y: top), control: CGPoint(x: x1, y: top))
        p.closeSubpath()
        #if DEBUG
        if probe { DebugHooks.AnimPerfProbe.recordShape(CGRect(x: x0, y: top, width: w, height: h)) }
        #endif
        return p
    }

    var body: some View {
        self.fill(.black)
    }
}
