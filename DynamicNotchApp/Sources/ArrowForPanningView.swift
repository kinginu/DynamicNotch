import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
import SwiftUI

struct ArrowForPanningView: View {
    // Direction flag at self+9: bit 0 controls arrow direction (XOR 1 reverses)
    // isPressed flag at self+1 byte
    // First field = fade distance (used as divisor for interpolation)

    // Uses interpolatorBuilder with UnitCurve.linear
    // Scale: if isPressed, fixed scale (0.75 + 0.25*interpolation)
    // Offset: if isPressed, -32 or +32 based on direction; else offset = value * 0.5
    // Animation: spring(response:0.2, dampingFraction:0.2)
    // ABS of first field for fade distance; divides by 24.0 for interpolation input
    var body: some View {
        HStack {
            // frame: width=24, height=10, center alignment
            RoundedTriangle()
                .frame(width: 24, height: 10, alignment: .center)
            RoundedTriangle()
                .frame(width: 24, height: 10, alignment: .center)
        }
        // isPressed check at self+1: if pressed, scale = 0.75 + 0.25*interpolation
        .scaleEffect(0.75)
        .opacity(0.85)
        .offset(x: 0)
        .animation(.spring(response: 0.2, dampingFraction: 0.2))
    }
}
