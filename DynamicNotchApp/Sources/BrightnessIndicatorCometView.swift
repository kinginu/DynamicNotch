import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
import SwiftUI

struct BrightnessIndicatorCometView: Equatable, View {
    private var mainGradient: LinearGradient {
        LinearGradient(
            stops: [
                Gradient.Stop(color: .white.opacity(0.0), location: 0.0),
                Gradient.Stop(color: .white.opacity(0.6), location: 0.3),
                Gradient.Stop(color: .white.opacity(0.9), location: 0.6),
                Gradient.Stop(color: .white.opacity(1.0), location: 1.0),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // glowInterpolator — interpolator for blur transition
    private var glowInterpolator: interpolatorBuilder {
        let inputs: [CGFloat] = [0.0, 0.25, 0.50, 0.75, 1.0]
        let outputs: [CGFloat] = [0.0, 3.0, 7.0, 5.0, 0.0]
        return interpolatorBuilder(inputs: inputs, outputs: outputs, curve: .linear)
    }

    // overflowInterpolator — interpolator for overflow scale clamp
    private var overflowInterpolator: interpolatorBuilder {
        let inputs: [CGFloat] = [0.0, 0.5, 0.75, 1.0]
        let outputs: [CGFloat] = [1.0, 1.0, 1.25, 1.25]
        return interpolatorBuilder(inputs: inputs, outputs: outputs, curve: .linear)
    }

    var body: some View {
        HorizontalCometShape()
            // 8-layer drop shadow with Color.opacity:
            // Layer 2: radius=56
            .shadow(color: .white.opacity(0.5), radius: 56, x: 0, y: 0)
            .shadow(color: .white.opacity(0.3), radius: 56, x: 0, y: 0)
            .shadow(color: .white.opacity(0.2), radius: 32, x: 0, y: 0)
            .shadow(color: .white.opacity(0.2), radius: 24, x: 0, y: 0)
            .shadow(color: .white.opacity(0.15), radius: 16, x: 0, y: 0)
            .shadow(color: .white.opacity(0.1), radius: 12, x: 0, y: 0)
            .shadow(color: .white.opacity(0.08), radius: 4, x: 0, y: 0)
            .shadow(color: .white.opacity(0.05), radius: 1, x: 0, y: 0)
            // frame: height from parameter, fill horizontal width
            .frame(
                width: nil as CGFloat?,
                height: 30,
                alignment: .center
            )
            // blur effect (interpolated from glowInterpolator via CGFloat)
            .blur(radius: 0)
            .zIndex(1.0)
    }
}
