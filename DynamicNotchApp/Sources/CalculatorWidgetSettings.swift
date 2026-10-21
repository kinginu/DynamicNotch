// Settings of the Calculator widget (2026-10-20). Key "calculatorWidgetSettings"
// (typed key still in Support/Ext-C.swift; pattern: SettingsUI/SettingsDecoding.swift). The
// result history and the exchange-rate cache live in Application Support (CalculatorStores.swift).
import Foundation

struct CalculatorWidgetSettings: Preferences, WidgetPrefs, Codable, Equatable, Hashable {
    /// Currency pair used when an amount has no target: "100 usd" converts `fromCurrency` →
    /// `toCurrency` (and an amount already in `toCurrency` converts back).
    var fromCurrency: String = "USD"
    var toCurrency: String = "JPY"
    /// Maximum fraction digits of results (money keeps its own digits, at most this many).
    var decimalDigits: Int = 6
    /// Put the keyboard focus in the field when the Nook opens. The notch then stays open while
    /// the field has text; an empty field gives the focus back when the pointer leaves the notch.
    var focusOnOpen: Bool = true

    static let decimalDigitChoices = [0, 2, 4, 6, 8, 10]

    static let `default` = CalculatorWidgetSettings()

    var gridSizeType: NookWidget.NookGridSizeType { .small }

    init() {}

    // Tolerant decoding: a missing or undecodable field keeps its default.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.decodeSetting(.fromCurrency, into: &fromCurrency)
        c.decodeSetting(.toCurrency, into: &toCurrency)
        c.decodeSetting(.decimalDigits, into: &decimalDigits)
        c.decodeSetting(.focusOnOpen, into: &focusOnOpen)
        decimalDigits = min(max(decimalDigits, 0), 12)
    }

    private enum CodingKeys: String, CodingKey {
        case fromCurrency, toCurrency, decimalDigits, focusOnOpen
    }
}
