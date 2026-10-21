import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// Scales the label down while pressed
// (`ShrinkOnClick(minSize: 0.85)` at call sites).
struct ShrinkOnClick: ButtonStyle {
    var minSize: CGFloat = 0.9

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? minSize : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
