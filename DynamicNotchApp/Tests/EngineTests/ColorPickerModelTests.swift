// Tests of the Color Picker model (Sources/ColorPickerModel.swift): text formats, HSL, WCAG
// contrast and the recent-colours list.
import Foundation
import Testing
@testable import DynamicNotchApp   // the CLT harness library and the Xcode test-support library

private let t0 = Date(timeIntervalSince1970: 1_792_400_000)

@Suite("Color Picker model")
struct ColorPickerModelTests {

    struct FormatCase: Sendable, CustomTestStringConvertible {
        var r: Double, g: Double, b: Double
        var hex: String, rgb: String, hsl: String
        var testDescription: String { hex }
    }

    static let formats: [FormatCase] = [
        .init(r: 1, g: 0, b: 0, hex: "#FF0000", rgb: "rgb(255, 0, 0)", hsl: "hsl(0, 100%, 50%)"),
        .init(r: 0, g: 1, b: 0, hex: "#00FF00", rgb: "rgb(0, 255, 0)", hsl: "hsl(120, 100%, 50%)"),
        .init(r: 0, g: 0, b: 1, hex: "#0000FF", rgb: "rgb(0, 0, 255)", hsl: "hsl(240, 100%, 50%)"),
        .init(r: 1, g: 0, b: 1, hex: "#FF00FF", rgb: "rgb(255, 0, 255)", hsl: "hsl(300, 100%, 50%)"),   // red max, g < b
        .init(r: 0, g: 0.478, b: 1, hex: "#007AFF", rgb: "rgb(0, 122, 255)", hsl: "hsl(211, 100%, 50%)"),
        .init(r: 0.5, g: 0.5, b: 0.5, hex: "#808080", rgb: "rgb(128, 128, 128)", hsl: "hsl(0, 0%, 50%)"),
        .init(r: 1, g: 1, b: 1, hex: "#FFFFFF", rgb: "rgb(255, 255, 255)", hsl: "hsl(0, 0%, 100%)"),
        .init(r: 0, g: 0, b: 0, hex: "#000000", rgb: "rgb(0, 0, 0)", hsl: "hsl(0, 0%, 0%)"),
        .init(r: 2, g: -1, b: .nan, hex: "#FF0000", rgb: "rgb(255, 0, 0)", hsl: "hsl(0, 100%, 50%)"),   // clamped
    ]

    @Test(arguments: formats)
    func formats(_ c: FormatCase) {
        let color = PickedColor(red: c.r, green: c.g, blue: c.b)
        #expect(color.formatted(.hex) == c.hex)
        #expect(color.formatted(.hex, uppercaseHex: false) == c.hex.lowercased())
        #expect(color.formatted(.rgb) == c.rgb)
        #expect(color.formatted(.hsl) == c.hsl)
    }

    @Test func swiftLiteralsUsePOSIXDecimals() {
        let c = PickedColor(red: 0.5, green: 0.25, blue: 1)
        #expect(c.formatted(.swiftUI) == "Color(red: 0.500, green: 0.250, blue: 1.000)")
        #expect(c.formatted(.nsColor) == "NSColor(srgbRed: 0.500, green: 0.250, blue: 1.000, alpha: 1)")
    }

    @Test func contrast() {
        let white = PickedColor(red: 1, green: 1, blue: 1), black = PickedColor(red: 0, green: 0, blue: 0)
        #expect(abs(black.contrastOnWhite - 21) < 1e-9)
        #expect(abs(white.contrastOnBlack - 21) < 1e-9)
        #expect(white.prefersDarkText)
        #expect(!black.prefersDarkText)
        #expect(PickedColor.wcagLevel(21) == "AAA")
        #expect(PickedColor.wcagLevel(4.5) == "AA")
        #expect(PickedColor.wcagLevel(3) == "AA Large")
        #expect(PickedColor.wcagLevel(2.9) == nil)
        #expect(PickedColor.ratioText(4.54) == "4.5:1")
    }

    @Test func sameValueAt8Bit() {
        #expect(PickedColor(red: 0.5, green: 0, blue: 0).hasSameValue(as: PickedColor(red: 0.501, green: 0, blue: 0)))
        #expect(!PickedColor(red: 0.5, green: 0, blue: 0).hasSameValue(as: PickedColor(red: 0.51, green: 0, blue: 0)))
    }

    // MARK: History

    @Test func addingDedupesAnywhereAndLimits() {
        let red = PickedColor(red: 1, green: 0, blue: 0), green = PickedColor(red: 0, green: 1, blue: 0)
        let blue = PickedColor(red: 0, green: 0, blue: 1)
        var list: [PickedColor] = []
        list = ColorPickerHistoryList.adding(red, to: list, limit: 3)
        list = ColorPickerHistoryList.adding(green, to: list, limit: 3)
        list = ColorPickerHistoryList.adding(blue, to: list, limit: 3)
        let redAgain = PickedColor(red: 1, green: 0.001, blue: 0)          // same 8-bit value
        list = ColorPickerHistoryList.adding(redAgain, to: list, limit: 3)
        #expect(list.map { $0.formatted(.hex) } == ["#FF0000", "#0000FF", "#00FF00"])
        #expect(list[0].id == redAgain.id)
        list = ColorPickerHistoryList.adding(PickedColor(red: 1, green: 1, blue: 0), to: list, limit: 3)
        #expect(list.map { $0.formatted(.hex) } == ["#FFFF00", "#FF0000", "#0000FF"])
        #expect(ColorPickerHistoryList.adding(red, to: list, limit: 0).count == 1)   // floor of 1
    }

    @Test func selectingMovesToFront() {
        let a = PickedColor(red: 1, green: 0, blue: 0, date: t0), b = PickedColor(red: 0, green: 1, blue: 0, date: t0)
        let (list, moved) = ColorPickerHistoryList.selecting(b, in: [a, b], date: t0.addingTimeInterval(5))
        #expect(list.map(\.id) == [b.id, a.id])
        #expect(moved.date == t0.addingTimeInterval(5))
        #expect(list[0] == moved)
    }

    @Test func trimmed() {
        let list = (0..<5).map { PickedColor(red: Double($0) / 4, green: 0, blue: 0) }
        #expect(ColorPickerHistoryList.trimmed(list, limit: 2).count == 2)
        #expect(ColorPickerHistoryList.trimmed(list, limit: 10).count == 5)
        #expect(ColorPickerHistoryList.trimmed(list, limit: -1).count == 1)
    }
}
