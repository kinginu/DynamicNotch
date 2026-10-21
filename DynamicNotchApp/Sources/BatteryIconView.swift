import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import SwiftUI

// Battery icon with jiggle animation when low
struct BatteryIconView: View {

    // Battery charge level (0.0...1.0)
    var level: CGFloat = 1.0

    // Whether currently charging
    var isCharging: Bool = false

    // Jiggle animation state
    @State private var isJiggling: Bool = false

    // MARK: - Body

    // ZStack with battery shape, charge level trim, and charging indicator
    var body: some View {
        ZStack {
            // Battery body outline
            // the "…bolt" symbol already carries the charging glyph (the separate
            //   bolt overlay doubled it)
            Image(systemName: isCharging ? "battery.100percent.bolt" : batteryIconName())
                .foregroundStyle(levelColor())
                .font(.system(size: 15, weight: .regular))
        }
        .rotationEffect(
            Angle(degrees: isJiggling ? 5 : 0),
            anchor: .center
        )
        .onAppear {
            if level < 0.1 {
                startJiggleAnimation()
            }
        }
    }

    // MARK: - startJiggleAnimation

    // startJiggleAnimation()
    // Dispatch-based jiggle animation loop (ease-in-out, repeat 6x, auto-reverse)
    func startJiggleAnimation() {
        guard !isJiggling else { return }
        isJiggling = true

        // Animate jiggle with spring/easeInOut
        withAnimation(
            .easeInOut(duration: 0.1)
                .repeatCount(6, autoreverses: true)
        ) {
            // Toggle back after animation
        }

        // Schedule reset after animation completes (0.15s delayed)
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.15,
            qos: .unspecified,
            flags: []
        ) { [self] in
            isJiggling = false
        }
    }

    // Select battery icon name based on level
    private func batteryIconName() -> String {
        switch level {
        case 0.75...:   return "battery.100"
        case 0.5...:    return "battery.75"
        case 0.25...:   return "battery.50"
        case 0.1...:    return "battery.25"
        default:        return "battery.0"
        }
    }

    // Color based on battery level
    private func levelColor() -> Color {
        if isCharging { return .green }
        if level < 0.1 { return .red }
        if level < 0.25 { return .orange }
        if level < 0.5 { return .yellow }
        return .white
    }
}