import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import AppKit
import SwiftUI

// A bubble-style elliptical outline shape with capsule ends.
//   Used for capsule-shaped glass container outlines.
struct BubbleOutlineShape: Animatable, Shape, View {

    // Stroke width
    var strokeWidth: CGFloat = 1.0

    var animatableData: CGFloat {
        get { strokeWidth }
        set { strokeWidth = newValue }
    }

    func path(in rect: CGRect) -> Path {
        // Capsule-style rounded rect (fully rounded ends)
        let minDim = min(rect.width, rect.height)
        let radius = minDim / 2.0
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        return Path(path)
    }

    var body: some View {
        self
            .fill(.clear)
            .overlay(self.stroke(.white.opacity(0.15), lineWidth: strokeWidth))
    }
}
