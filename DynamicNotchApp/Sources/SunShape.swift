import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import AppKit
import SwiftUI

// Sun shape — a circle with radiating "rays" for a sun icon or
//   decorative element. Used in brightness/volume indicators.
struct SunShape: Animatable, Shape, View {

    // Number of sun rays
    var rayCount: Int = 12

    // Inner radius fraction (0...1 relative to outer)
    var innerRadiusFraction: CGFloat = 0.6

    // Ray length extension beyond the circle
    var rayLength: CGFloat = 0.15

    var animatableData: CGFloat {
        get { innerRadiusFraction }
        set { innerRadiusFraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2.0
        let innerRadius = outerRadius * innerRadiusFraction
        let rayOuterRadius = outerRadius * (1.0 + rayLength)

        var path = Path()

        for i in 0..<rayCount {
            let angle = CGFloat(i) * (2.0 * .pi / CGFloat(rayCount)) - .pi / 2.0

            // Inner point on circle
            let ix = center.x + innerRadius * cos(angle)
            let iy = center.y + innerRadius * sin(angle)

            // Outer ray tip
            let rayAngle = angle
            let ox = center.x + rayOuterRadius * cos(rayAngle)
            let oy = center.y + rayOuterRadius * sin(rayAngle)

            // Next inner point
            let nextAngle = CGFloat(i + 1) * (2.0 * .pi / CGFloat(rayCount)) - .pi / 2.0
            let nx = center.x + innerRadius * cos(nextAngle)
            let ny = center.y + innerRadius * sin(nextAngle)

            path.move(to: CGPoint(x: ix, y: iy))
            path.addLine(to: CGPoint(x: ox, y: oy))
            path.addLine(to: CGPoint(x: nx, y: ny))
        }

        return path
    }

    var body: some View {
        self.fill(
            RadialGradient(
                colors: [Color.yellow.opacity(0.8), Color.orange.opacity(0.4)],
                center: .center,
                startRadius: 0,
                endRadius: 100
            )
        )
    }
}
