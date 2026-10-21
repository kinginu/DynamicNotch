import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import AppKit
import SwiftUI

// A geometry effect that applies a deformation based on scroll position.
//   Creates a perspective/parallax feel as items scroll — items appear to
//   "bend" or "deform" slightly based on their position in the scroll container.
struct ScrollDeformEffect: GeometryEffect { // GeometryEffect already implies Animatable + ViewModifier

    // Intensity of the deformation effect
    var intensity: CGFloat = 0.05

    // Current scroll offset (coming from the parent scroll context)
    var scrollOffset: CGFloat = 0.0

    var animatableData: CGFloat {
        get { intensity }
        set { intensity = newValue }
    }

    //   Based on the size and the current scroll offset, creates a slight
    //   perspective rotation that gives the "deformation" visual.
    func effectValue(size: CGSize) -> ProjectionTransform {
        // Calculate deformation based on scroll position and item size
        //   The higher the scroll, the more perspective "bend" applied
        // build as CATransform3D, convert to ProjectionTransform at the end
        var transform = CATransform3DIdentity

        // Slight Y-axis rotation for parallax feel
        let midY = size.height / 2.0
        let normalizedOffset = scrollOffset / max(size.height, 1.0)
        let angle = normalizedOffset * intensity * .pi

        transform.m34 = -1.0 / 500.0
        transform = CATransform3DRotate(transform, angle, 1, 0, 0)

        return ProjectionTransform(transform)
    }
    // body(content:) removed: GeometryEffect supplies its own
}
