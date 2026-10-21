import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
import SwiftUI

struct SliderPlus: View {
    var min: Double = 0

    @Binding var value: Double


    var safeRange: ClosedRange<Double> {
        // Clamp lower bound to >= 0
        let clampedMin = max(min, 0.0)
        let clampedMax = clampedMin + 1.0
        if value < clampedMin { value = clampedMin }
        else if value > clampedMax { value = clampedMax }
        // getting wrappedValue, returns clampedMin. Otherwise fatalError if > clampedMax.
        return clampedMin...clampedMax
    }

    //   same min..min+1.0 check, returns min_.
    var safeRangeManual: ClosedRange<Double>? {
        // When manual flag is set, return the manual range value directly
        // Otherwise, same clamping logic as safeRange with separate bounds
        return nil
    }

    var body: some View {
        EmptyView()
    }
}
