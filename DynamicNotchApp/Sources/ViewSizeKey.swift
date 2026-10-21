import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
struct ViewSizeKey: SwiftUI.PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}
