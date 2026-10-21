import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
import SwiftUI

// Signed height offset ("+4", "-2") in a 40 pt leading-aligned label with a numeric-text
//   transition.

struct HeightFineTuningView: View {

    var height: Double

    var body: some View {
        Text("\(height >= 0 ? "+" : "")\(Int(height))")
            .contentTransition(.numericText(countsDown: false))

            .fixedSize()

            .foregroundStyle(Color.fineTuningBG)

            .fontWeight(.semibold)

            .frame(width: 40, alignment: .leading)

            .animation(.spring(response: 0.0, dampingFraction: 1.0, blendDuration: 0.0), value: height)
    }
}
