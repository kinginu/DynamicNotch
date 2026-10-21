import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// Button style used by LockedIndicatorView: passes the
// label through unchanged with a light pressed-state dim.
struct BindStatesStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}
