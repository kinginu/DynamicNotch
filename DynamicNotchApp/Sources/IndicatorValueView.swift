import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// Percentage label for an indicator value
struct IndicatorValueView: Equatable, View {
    var value: Double = 0

    var body: some View {
        Text("\(Int((value * 100).rounded()))%")
            .font(.system(size: 12, weight: .semibold))
            .monospacedDigit()
            .contentTransition(.numericText())
    }
}
