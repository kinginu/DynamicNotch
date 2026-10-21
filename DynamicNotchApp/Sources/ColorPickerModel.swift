// Color Picker widget model (2026-10-20): a picked colour, its text formats, HSL, WCAG
// contrast, and the recent-colours list rules. Pure Foundation (the NSColor / SwiftUI bridges and
// the sampler are in ColorPickerHistory.swift). Tests: Tests/EngineTests/ColorPickerModelTests.swift.
//
// Values are sRGB components clamped to 0…1 (non-finite → 0). Formats: "#RRGGBB" (8-bit,
// rounded), "rgb(r, g, b)", "hsl(h, s%, l%)" (rounded; hue 0…359), and Swift literals with three
// decimals in the POSIX locale. Two colours are "the same" at 8-bit precision.
//
// History (newest first, at most `limit` ≥ 1): adding a colour removes every earlier entry with the
// same 8-bit value (not only the newest), selecting an entry moves it to the front with a new date.
import Foundation

struct PickedColor: Codable, Hashable, Identifiable {
    var id = UUID()
    /// sRGB components, 0…1.
    var red: Double
    var green: Double
    var blue: Double
    var date = Date()

    init(red: Double, green: Double, blue: Double, date: Date = Date()) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
        self.date = date
    }

    private static func clamp(_ v: Double) -> Double { v.isFinite ? min(max(v, 0), 1) : 0 }

    /// 8-bit channel values.
    var bytes: (r: Int, g: Int, b: Int) {
        (Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    /// Same colour at 8-bit precision (merges re-picks of the same pixel colour).
    func hasSameValue(as other: PickedColor) -> Bool { bytes == other.bytes }

    // MARK: Formats

    func hex(uppercase: Bool = true) -> String {
        let (r, g, b) = bytes
        let s = String(format: "#%02x%02x%02x", r, g, b)
        return uppercase ? s.uppercased() : s
    }

    /// Hue in degrees (0…360), saturation and lightness in 0…1.
    var hsl: (h: Double, s: Double, l: Double) {
        let maxC = max(red, green, blue), minC = min(red, green, blue)
        let l = (maxC + minC) / 2
        let d = maxC - minC
        guard d > 0 else { return (0, 0, l) }
        let s = d / (1 - abs(2 * l - 1))
        var h: Double
        switch maxC {
        case red: h = ((green - blue) / d).truncatingRemainder(dividingBy: 6)
        case green: h = (blue - red) / d + 2
        default: h = (red - green) / d + 4
        }
        h *= 60
        if h < 0 { h += 360 }
        return (h, s, l)
    }

    func formatted(_ format: ColorCopyFormat, uppercaseHex: Bool = true) -> String {
        switch format {
        case .hex:
            return hex(uppercase: uppercaseHex)
        case .rgb:
            let (r, g, b) = bytes
            return "rgb(\(r), \(g), \(b))"
        case .hsl:
            let (h, s, l) = hsl
            let hh = Int(h.rounded()) % 360
            return "hsl(\(hh), \(Int((s * 100).rounded()))%, \(Int((l * 100).rounded()))%)"
        case .swiftUI:
            return "Color(red: \(Self.decimal(red)), green: \(Self.decimal(green)), blue: \(Self.decimal(blue)))"
        case .nsColor:
            return "NSColor(srgbRed: \(Self.decimal(red)), green: \(Self.decimal(green)), blue: \(Self.decimal(blue)), alpha: 1)"
        }
    }

    /// Three decimals, POSIX locale (code must not depend on the user's decimal separator).
    private static func decimal(_ v: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), v)
    }

    // MARK: Contrast (WCAG 2.x)

    /// Relative luminance (WCAG 2.x, sRGB).
    var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(red) + 0.7152 * lin(green) + 0.0722 * lin(blue)
    }

    /// Contrast ratio against white (1…21).
    var contrastOnWhite: Double { 1.05 / (luminance + 0.05) }
    /// Contrast ratio against black (1…21).
    var contrastOnBlack: Double { (luminance + 0.05) / 0.05 }
    /// Text colour that reads better on this colour.
    var prefersDarkText: Bool { contrastOnBlack >= contrastOnWhite }

    /// WCAG level reached by a contrast ratio for normal text.
    static func wcagLevel(_ ratio: Double) -> String? {
        if ratio >= 7 { return "AAA" }
        if ratio >= 4.5 { return "AA" }
        if ratio >= 3 { return "AA Large" }
        return nil
    }

    static func ratioText(_ ratio: Double) -> String {
        String(format: "%.1f:1", locale: Locale(identifier: "en_US_POSIX"), ratio)
    }
}

/// How the recent-colours list changes (newest first).
enum ColorPickerHistoryList {
    static func normalizedLimit(_ limit: Int) -> Int { max(limit, 1) }

    /// `color` on top; earlier entries with the same 8-bit value are removed; at most `limit`.
    static func adding(_ color: PickedColor, to list: [PickedColor], limit: Int) -> [PickedColor] {
        var list = list
        list.removeAll { $0.hasSameValue(as: color) }
        list.insert(color, at: 0)
        return trimmed(list, limit: limit)
    }


    static func selecting(_ color: PickedColor, in list: [PickedColor], date: Date) -> ([PickedColor], PickedColor) {
        var moved = color
        moved.date = date
        var list = list
        list.removeAll { $0.id == color.id }
        list.insert(moved, at: 0)
        return (list, moved)
    }

    static func trimmed(_ list: [PickedColor], limit: Int) -> [PickedColor] {
        Array(list.prefix(normalizedLimit(limit)))
    }
}
