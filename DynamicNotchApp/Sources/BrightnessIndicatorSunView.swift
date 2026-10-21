import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
import SwiftUI

struct BrightnessIndicatorSunView: Equatable, View {
    @State private var isActive: Bool = false

    private var glowInterpolator: interpolatorBuilder {
        let inputs: [CGFloat] = [0.0, 0.25, 0.50, 0.75, 1.0]
        let outputs: [CGFloat] = [0.0, 4.0, 8.0, 6.0, 0.0]
        return interpolatorBuilder(inputs: inputs, outputs: outputs, curve: .linear)
    }

    private var overflowInterpolator: interpolatorBuilder {
        let inputs: [CGFloat] = [0.0, 0.5, 0.75, 1.0]
        let outputs: [CGFloat] = [1.0, 1.0, 1.25, 1.25]
        return interpolatorBuilder(inputs: inputs, outputs: outputs, curve: .linear)
    }

    var body: some View {
        // stroked sun with an eight-layer glow; tilts and drops slightly when active
        SunShape()
            .stroke(lineWidth: 10)
            .shadow(color: .nonShockingWhite.opacity(0.5), radius: 56, x: 0, y: 0)
            .shadow(color: .nonShockingWhite.opacity(0.3), radius: 56, x: 0, y: 0)
            .shadow(color: .nonShockingWhite.opacity(0.2), radius: 32, x: 0, y: 0)
            .shadow(color: .nonShockingWhite.opacity(0.2), radius: 24, x: 0, y: 0)
            .shadow(color: .nonShockingWhite.opacity(0.15), radius: 16, x: 0, y: 0)
            .shadow(color: .nonShockingWhite.opacity(0.1), radius: 12, x: 0, y: 0)
            .shadow(color: .nonShockingWhite.opacity(0.08), radius: 4, x: 0, y: 0)
            .shadow(color: .nonShockingWhite.opacity(0.05), radius: 1, x: 0, y: 0)
            .background(EmptyView())
            .frame(width: 25, height: 25, alignment: .center)
            .blur(radius: 0)
            .scaleEffect(1.0, anchor: .center)
            .rotation3DEffect(
                isActive ? .radians(-0.33) : .radians(0),
                axis: (x: 0, y: 0, z: 1),
                anchor: .center
            )
            .offset(x: 0, y: isActive ? 6.0 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.35)) {
                    isActive = true
                }
            }
    }

    // @State is not Equatable
    static func == (lhs: Self, rhs: Self) -> Bool { true }
}
