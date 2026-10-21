import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import Foundation
import SwiftUI

// MARK: - BrightnessIndicatorValueView

struct BrightnessIndicatorValueView: Equatable, View {

    // MARK: - Stored properties

    let brightness: Double

    // Overglow threshold (brightness is capped at 15.0 by the interpolators)
    let glowThreshold: Double

    // MARK: - textGradientColor1

    //   red:   interp * 0.2343 + 0.75, clamped [0.75, 0.9843]
    //   blue:  interp * 0.1049 + 0.75, clamped [0.75, 0.8549]
    //   green: interp * -0.25 + 1.0, clamped [0.75, 1.0]
    //   opacity: interp * 0.1 + 0.75, clamped [0.75, 0.85]
    //   Color(sRGBLinear, red:red, green:green, blue:blue, opacity:opacity)
    var textGradientColor1: Color {
        let interp = glowInterpolator

        var red = interp * 0.2343 + 0.75
        if red > 0.9843 { red = 0.9843 }
        if red < 0.75 { red = 0.75 }

        var blue = interp * 0.1049 + 0.75
        if blue > 0.8549 { blue = 0.8549 }
        if blue < 0.75 { blue = 0.75 }

        var green = interp * -0.25 + 1.0
        if green > 1.0 { green = 1.0 }
        if green < 0.75 { green = 0.75 }

        var opacity = interp * 0.1 + 0.75
        if opacity > 0.85 { opacity = 0.85 }
        if opacity < 0.75 { opacity = 0.75 }

        return Color(.sRGBLinear, red: red, green: green, blue: blue, opacity: opacity)
    }

    // MARK: - textGradientColor2

    //   red:   interp * -0.1971 + 0.75, clamped [0.5529, 0.75]
    //   green: interp * 0.0225 + 0.75, clamped [0.75, 0.7725]
    //   blue:  interp * -0.5 + 1.0, clamped [0.5, 1.0] → then mix with interp: (blue-0.75)*interp+0.75, min with 0.75
    //   opacity: interp * 0.1 + 0.75, clamped [0.75, 0.85]
    var textGradientColor2: Color {
        let interp = glowInterpolator

        var red = interp * -0.1971 + 0.75
        if red < 0.5529 { red = 0.5529 }
        if red > 0.75 { red = 0.75 }

        var green = interp * 0.0225 + 0.75
        if green > 0.7725 { green = 0.7725 }
        if green < 0.75 { green = 0.75 }

        var blue = interp * -0.5 + 1.0
        if blue > 1.0 { blue = 1.0 }
        if blue < 0.5 { blue = 0.5 }
        blue = min(blue, (blue - 0.75) * interp + 0.75)

        var opacity = interp * 0.1 + 0.75
        if opacity > 0.85 { opacity = 0.85 }
        if opacity < 0.75 { opacity = 0.75 }

        return Color(.sRGBLinear, red: red, green: green, blue: blue, opacity: opacity)
    }

    // MARK: - textGradientColor3

    //   red:   interp * -0.1971 + 0.75, clamped [0.5529, 0.75]
    //   green: interp * 0.0225 + 0.75, clamped [0.75, 0.7725]
    //   blue:  interp * -0.75 + 1.0, clamped [0.25, 1.0] → then mix: (blue-0.75)*interp+0.75, min with 0.75
    //   opacity: interp * -0.4 + 0.75, clamped [0.35, 0.75]
    var textGradientColor3: Color {
        let interp = glowInterpolator

        var red = interp * -0.1971 + 0.75
        if red < 0.5529 { red = 0.5529 }
        if red > 0.75 { red = 0.75 }

        var green = interp * 0.0225 + 0.75
        if green > 0.7725 { green = 0.7725 }
        if green < 0.75 { green = 0.75 }

        var blue = interp * -0.75 + 1.0
        if blue > 1.0 { blue = 1.0 }
        if blue < 0.25 { blue = 0.25 }
        blue = min(blue, (blue - 0.75) * interp + 0.75)

        var opacity = interp * -0.4 + 0.75
        if opacity > 0.75 { opacity = 0.75 }
        if opacity < 0.35 { opacity = 0.35 }

        return Color(.sRGBLinear, red: red, green: green, blue: blue, opacity: opacity)
    }

    // MARK: - Interpolators

    // Brightness 0…15 mapped linearly to 0…1; each textGradientColor applies its own
    //   per-channel coefficients to it.
    private var glowInterpolator: Double {
        let capped = min(brightness, 15.0)
        let raw = UnitCurve.linear.value(at: capped / 15.0)
        return raw
    }

    // Blur radius of the label: the same linear mapping, halved and clamped to 0…0.5.
    private var overflowInterpolator: Double {
        let capped = min(brightness, 15.0)
        let raw = UnitCurve.linear.value(at: capped / 15.0)
        var result = raw * 0.5
        if result > 0.5 { result = 0.5 }
        if result < 0.0 { result = 0.0 }
        return result
    }

    // MARK: - body

    //   geometryGroup → blur(overflowInterpolator) → foregroundStyle(EllipticalGradient(3 colors)) →
    //   font(.system(size:12, weight:.semibold, design:default)) → zIndex(2)
    var body: some View {
        let percentageValue = Int(brightness * 100.0)
        // localized as the "%lld%%" key
        let key: LocalizedStringKey = "\(percentageValue)%"

        let gradientColors = Gradient(colors: [
            textGradientColor3, textGradientColor2, textGradientColor1
        ])

        //   startRadiusFraction: brightness==1.0 ? 0.25 : 0.375
        //   endRadiusFraction: 1.0
        let startRadius: Double = (fabs(brightness - 1.0) < 0.0001) ? 0.25 : 0.375
        let gradient = EllipticalGradient(
            gradient: gradientColors,
            center: UnitPoint(x: 0.33, y: 0.33),
            startRadiusFraction: startRadius,
            endRadiusFraction: 1.0
        )

        Text(key, tableName: nil, bundle: nil, comment: nil)
            .fixedSize()
            .contentTransition(.identity)
            .geometryGroup()
            .blur(radius: overflowInterpolator)
            .foregroundStyle(gradient)
            .font(.system(size: 12, weight: .semibold, design: .default))
            .zIndex(2)
    }
}
