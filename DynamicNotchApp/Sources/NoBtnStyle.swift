import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// A button style that draws nothing extra.
struct NoBtnStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
    }
}
