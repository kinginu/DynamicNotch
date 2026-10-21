import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
import SwiftUI

struct ActionButton: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            // EdgeInsets: 8 leading/trailing=12
            .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            // Capsule fill: Color.blue
            .background(Capsule().fill(Color.blue))
            .brightness(configuration.isPressed ? 0.1 : 0)
            // foregroundStyle: nonShockingWhite
            .foregroundStyle(.nonShockingWhite)
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0, anchor: .center)
            // animation: spring(response:0.35, dampingFraction:0.5)
            .animation(.spring(response: 0.35, dampingFraction: 0.5), value: configuration.isPressed)
    }
}
