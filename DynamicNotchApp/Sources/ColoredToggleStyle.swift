import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// Switch-like toggle tinted with `color`.
struct ColoredToggleStyle: SwiftUI.ToggleStyle {
    var color: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 8)
            Capsule()
                .fill(configuration.isOn ? color : Color.secondary.opacity(0.3))
                .frame(width: 32, height: 18)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle().fill(.white).padding(2)
                }
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isOn)
                .onTapGesture { configuration.isOn.toggle() }
        }
    }
}
