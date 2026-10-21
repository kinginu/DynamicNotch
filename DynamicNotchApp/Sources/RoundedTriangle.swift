import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// Upward-pointing triangle with rounded corners
struct RoundedTriangle: Animatable, Shape {
    var cornerRadius: CGFloat = 2.0

    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let top = CGPoint(x: rect.midX, y: rect.minY)
        let right = CGPoint(x: rect.maxX, y: rect.maxY)
        let left = CGPoint(x: rect.minX, y: rect.maxY)
        var path = Path()
        path.move(to: CGPoint(x: (left.x + right.x) / 2, y: rect.maxY))
        path.addArc(tangent1End: right, tangent2End: top, radius: cornerRadius)
        path.addArc(tangent1End: top, tangent2End: left, radius: cornerRadius)
        path.addArc(tangent1End: left, tangent2End: right, radius: cornerRadius)
        path.closeSubpath()
        return path
    }
}
