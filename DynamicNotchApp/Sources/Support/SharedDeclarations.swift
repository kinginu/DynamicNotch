// Shared declarations: the settings protocols (`Preferences`, `WidgetPrefs`, `MetaInfo`), the
// piecewise-linear `interpolatorBuilder`, `Color.nonShockingWhite` and the `.scaleAndBlur`
// transition.
import SwiftUI

// MARK: - Preferences

/// Common protocol of the persisted settings structs
/// (`GeneralSettings`, `*WidgetSettings`, `*LiveActivitySettings`, …).
/// Use sites call `X.defaultValue` and store the values with `SettingsStore` (JSON string,
/// `CodableStoredValue`; formerly `Defaults.Serializable`).
protocol Preferences: CodableStoredValue, Hashable {
    init()
}

extension Preferences {
    /// `X.defaultValue` is used throughout the views (previews / env defaults).
    static var defaultValue: Self { Self() }
}

/// Settings of a Nook grid widget. `NookWidget.prefs` returns it and
/// `NookSettings.widgetsWidthInPoints` reads `prefs.gridSizeType.rawValue`.
/// Kept free of Self requirements so it can be used as an existential (`var prefs: WidgetPrefs`).
protocol WidgetPrefs {
    var gridSizeType: NookWidget.NookGridSizeType { get }
}

// MARK: - MetaInfo

/// Display metadata shared by `NookWidget` and `LiveActivity`.
protocol MetaInfo {
    var icon: String { get }
    var name: String { get }
}

// MARK: - interpolatorBuilder

/// Piecewise-linear interpolator over (inputs → outputs), as used by the
/// brightness indicator views (`interpolatorBuilder(inputs:outputs:curve:)`), as a callable struct.
struct interpolatorBuilder {
    let inputs: [CGFloat]
    let outputs: [CGFloat]
    let curve: UnitCurve

    init(inputs: [CGFloat], outputs: [CGFloat], curve: UnitCurve = .linear) {
        self.inputs = inputs
        self.outputs = outputs
        self.curve = curve
    }

    func callAsFunction(_ x: CGFloat) -> CGFloat {
        guard let first = inputs.first, let last = inputs.last, !outputs.isEmpty else { return 0 }
        if x <= first { return outputs[0] }
        if x >= last { return outputs[min(outputs.count, inputs.count) - 1] }
        for i in 1..<min(inputs.count, outputs.count) where x <= inputs[i] {
            let t = (x - inputs[i - 1]) / max(inputs[i] - inputs[i - 1], .ulpOfOne)
            let eased = CGFloat(curve.value(at: Double(t)))
            return outputs[i - 1] + (outputs[i] - outputs[i - 1]) * eased
        }
        return outputs[outputs.count - 1]
    }
}

// MARK: - Shared style helpers

extension Color {
    /// Off-white used across the notch UI instead of pure white.
    static let nonShockingWhite = Color(white: 0.92)
}

extension ShapeStyle where Self == Color {
    /// Lets `.nonShockingWhite` be used where a ShapeStyle is expected.
    static var nonShockingWhite: Color { Color.nonShockingWhite }
}

extension AnyTransition {
    /// Scale + blur + opacity transition (see ScaleAndBlurEffect).
    static var scaleAndBlur: AnyTransition {
        .modifier(
            active: ScaleAndBlurEffect(progress: 0),
            identity: ScaleAndBlurEffect(progress: 1)
        )
    }
}
