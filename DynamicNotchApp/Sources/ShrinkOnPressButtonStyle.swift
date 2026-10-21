import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import SwiftUI

// A custom ButtonStyle that applies a scale animation on press.
//   The button shrinks slightly when pressed and springs back on release,
//   providing tactile feedback for glass-style buttons.
struct ShrinkOnPressButtonStyle: ButtonStyle {

    // Scale factor when pressed
    var scaleAmount: CGFloat = 0.95

    // Animation duration for press/release
    var animationDuration: Double = 0.15

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .scaleEffect(configuration.isPressed ? scaleAmount : 1.0)
            .animation(
                .spring(response: animationDuration, dampingFraction: 0.7),
                value: configuration.isPressed
            )
    }
}
