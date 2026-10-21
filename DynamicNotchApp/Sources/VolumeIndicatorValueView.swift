import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// Volume percentage from the environment indicator
struct VolumeIndicatorValueView: Equatable, View {
    @Environment(\.indicator) private var indicator

    var body: some View {
        IndicatorValueView(value: indicator?.value ?? 0)
    }

    static func == (lhs: Self, rhs: Self) -> Bool { true }
}
