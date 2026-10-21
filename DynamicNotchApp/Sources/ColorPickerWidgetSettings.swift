// Settings of the Color Picker widget (2026-10-20). Key "colorPickerWidgetSettings"
// (typed key still in Support/Ext-C.swift; pattern: SettingsUI/SettingsDecoding.swift). The
// picked colours themselves live in Application Support (ColorPickerHistoryStore).
import Foundation

/// Text copied to the pasteboard for a picked colour.
enum ColorCopyFormat: String, Codable, CaseIterable, Identifiable, Hashable {
    case hex          // #RRGGBB
    case rgb          // rgb(r, g, b)
    case hsl          // hsl(h, s%, l%)
    case swiftUI      // Color(red:green:blue:)
    case nsColor      // NSColor(srgbRed:green:blue:alpha:)

    var id: String { rawValue }

    /// Name shown in the format pickers (Localizable.strings key).
    var title: String {
        switch self {
        case .hex: return "HEX"
        case .rgb: return "RGB"
        case .hsl: return "HSL"
        case .swiftUI: return "SwiftUI Color"
        case .nsColor: return "NSColor"
        }
    }
}

struct ColorPickerWidgetSettings: Preferences, WidgetPrefs, Codable, Equatable, Hashable {
    /// Format copied after picking and when a history swatch is clicked.
    var format: ColorCopyFormat = .hex
    /// Copy the colour as soon as it is picked (otherwise only when the value is clicked).
    var copyOnPick: Bool = true
    /// `#A1B2C3` instead of `#a1b2c3`.
    var uppercaseHex: Bool = true
    /// Number of recent colours kept (oldest dropped).
    var historyLimit: Int = 12

    static let historyLimitChoices = [8, 10, 12]

    static let `default` = ColorPickerWidgetSettings()

    var gridSizeType: NookWidget.NookGridSizeType { .small }   // width: NookWidgetLayout.cells (4 = 200 pt)

    init() {}

    // Tolerant decoding: a missing or undecodable field keeps its default.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.decodeSetting(.format, into: &format)
        c.decodeSetting(.copyOnPick, into: &copyOnPick)
        c.decodeSetting(.uppercaseHex, into: &uppercaseHex)
        c.decodeSetting(.historyLimit, into: &historyLimit)
    }

    private enum CodingKeys: String, CodingKey {
        case format, copyOnPick, uppercaseHex, historyLimit
    }
}
