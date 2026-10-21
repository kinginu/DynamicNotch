import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import Foundation
import SwiftUI

// Slider component that supports negative value ranges.
//   rangeAmount computes the positive span: max(value, lowerBound) - lowerBound.
//   safeRange returns a ClosedRange from lowerBound up to:
//     max(max(value, lowerBound), lowerBound) + 1 (if value <= lowerBound).
struct SliderPlusNegative: View {

    // Current slider value binding
    @Binding var value: Double

    // Lower bound (can be negative)
    var lowerBound: Double

    // Upper bound
    var upperBound: Double

    // step used by the − / + buttons
    var step: Double = 0.1

    // A standard Slider over `safeRange` with − / + stepper buttons and the current value
    //   (Settings ▸ Live Activities ▸ Media ▸ Custom GIF ▸ Scale).
    var body: some View {
        HStack(spacing: 6) {
            Button {
                value = clamp(value - step)
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.borderless)
            .disabled(value <= safeRange.lowerBound)
            .accessibilityLabel(Text("Decrease"))

            Slider(value: Binding(get: { clamp(value) }, set: { value = clamp($0) }), in: safeRange)
                .controlSize(.small)

            Button {
                value = clamp(value + step)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .disabled(value >= safeRange.upperBound)
            .accessibilityLabel(Text("Increase"))

            Text(value, format: .number.precision(.fractionLength(1)))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 32, alignment: .trailing)
        }
        .accessibilityElement(children: .contain)
    }

    private func clamp(_ v: Double) -> Double {
        let r = safeRange
        // snap to the step so repeated −/+ do not accumulate floating-point noise
        let snapped = (v / step).rounded() * step
        return min(max(snapped, r.lowerBound), r.upperBound)
    }

    //   Computes: max(value, lowerBound) - lowerBound.
    //   If the computed max <= lowerBound, it adds 1.0 to prevent zero.
    //   Returns the positive span usable for slider display.
    var rangeAmount: Double {
        var clamped = upperBound

        let safeMin = lowerBound
        if clamped <= safeMin {
            clamped = max(value, safeMin)
        }
        if clamped <= safeMin {
            clamped += 1.0
        }

        var clampedMax = upperBound
        if clampedMax <= safeMin {
            clampedMax = max(value, safeMin)
        }
        if clampedMax <= safeMin {
            clampedMax += 1.0
        }

        return clampedMax - safeMin
    }

    //   Returns ClosedRange from lowerBound to:
    //     max(max(value, lowerBound), lowerBound) + 1
    var safeRange: ClosedRange<Double> {
        var effectiveMax = upperBound

        if effectiveMax <= lowerBound {
            effectiveMax = max(value, lowerBound)
        }
        if effectiveMax <= lowerBound {
            effectiveMax += 1.0
        }

        return lowerBound...effectiveMax
    }
}
