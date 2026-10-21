import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import AppKit
import SwiftUI

// Horizontal comet/trail shape for decorative effects.
//   Elongated oval tapering on one side, used for glow/light traces.
struct HorizontalCometShape: Animatable, Shape, View {

    // Progress of the comet animation (0...1)
    var progress: CGFloat = 0.5

    // Direction: true = left-to-right
    var isLeftToRight: Bool = true

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        // Horizontal comet path — a tapered oval
        let taperStart: CGFloat = isLeftToRight ? rect.minX : rect.maxX
        let taperEnd: CGFloat = isLeftToRight ? rect.maxX : rect.minX

        var path = Path()
        let midY = rect.midY
        let height = rect.height * (0.5 + progress * 0.5)

        path.move(to: CGPoint(x: taperStart, y: midY))
        path.addQuadCurve(
            to: CGPoint(x: taperEnd, y: midY - height / 2.0),
            control: CGPoint(x: (taperStart + rect.midX) / 2.0, y: midY - height)
        )
        path.addLine(to: CGPoint(x: taperEnd, y: midY + height / 2.0))
        path.addQuadCurve(
            to: CGPoint(x: taperStart, y: midY),
            control: CGPoint(x: (taperStart + rect.midX) / 2.0, y: midY + height)
        )

        return path
    }

    var body: some View {
        self.fill(LinearGradient(
            colors: [.white.opacity(0.4), .white.opacity(0.0)],
            startPoint: isLeftToRight ? .leading : .trailing,
            endPoint: isLeftToRight ? .trailing : .leading
        ))
    }
}
