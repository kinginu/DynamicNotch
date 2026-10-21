import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

// Frames of the drop targets for NotchViewModel.targetsCoords
//   ([String: CGRect], keyed by drop-target id, frames in SwiftUI global space).
struct DropAreaCoordPreferenceKey: SwiftUI.PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Publishes this view's global frame as drop target `id`.
    func dropAreaTarget(_ id: String) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: DropAreaCoordPreferenceKey.self,
                                       value: [id: proxy.frame(in: .global)])
            }
        }
    }
}
