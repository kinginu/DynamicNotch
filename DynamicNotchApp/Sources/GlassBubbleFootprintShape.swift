import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import AppKit
import SwiftUI

// A glass bubble foot-print shape — an oval/ovaloid with a
//   soft, blurred edge for foot-print-style glass highlights.
struct GlassBubbleFootprintShape: Animatable, Shape, View {

    // Vertical offset for the foot-print effect
    var offsetY: CGFloat = 0.0

    // Opacity for the foot-print
    var opacityFraction: CGFloat = 0.5

    var animatableData: CGFloat {
        get { offsetY }
        set { offsetY = newValue }
    }

    func path(in rect: CGRect) -> Path {
        // Elongated oval — wider than tall, positioned at bottom edge
        let width = rect.width * 0.7
        let height = rect.height * 0.3
        let ovalRect = CGRect(
            x: rect.midX - width / 2.0,
            y: rect.maxY - height + offsetY,
            width: width,
            height: height
        )
        return Path(ellipseIn: ovalRect)
    }

    var body: some View {
        self
            .fill(RadialGradient(
                colors: [.white.opacity(opacityFraction), .clear],
                center: .center,
                startRadius: 0,
                endRadius: max(200, 200)
            ))
    }
}
