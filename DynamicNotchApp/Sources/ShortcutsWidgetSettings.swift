// Settings of the Shortcuts widget. Key "shortcutsWidgetSettings" (typed key still
// in Support/Ext-C.swift; pattern: SettingsUI/SettingsDecoding.swift). The shortcuts shown are a
// separate key (`shortcutsWidgetSelection`, Support/Ext-A.swift).
import Foundation

struct ShortcutsWidgetSettings: Preferences, WidgetPrefs, Codable, Equatable, Hashable {
    // NotchView reads `.disabled` / `.gridPoint` on every widget settings value.
    var disabled: Bool = false
    var gridPoint: NookGrid.Point = NookGrid.Point(value: 0)
    /// Stored grid size (kept for stored-value compatibility).
    var gridSize: NookGrid.Size = NookGrid.Size(width: .init(value: 1), height: .init(value: 1))
    /// Show the shortcut name.
    var showName: Bool = true
    /// Show the shortcut icon.
    var showIcon: Bool = true
    /// Tint with the shortcut colour.
    var showColor: Bool = false

    private enum CodingKeys: String, CodingKey {
        case disabled, gridPoint, gridSize, showName, showIcon, showColor
    }

    static let `default` = ShortcutsWidgetSettings()

    /// Width in grid cells (`screenPoints.double * 50` pt).
    var screenPoints: NookGrid.Point { gridSize.width }

    var gridSizeType: NookWidget.NookGridSizeType { NookWidget.shortcuts.gridSizeType }
}

extension ShortcutsWidgetSettings {
    // Tolerant decoding: a missing or undecodable field keeps its default.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.decodeSetting(.disabled, into: &disabled)
        c.decodeSetting(.gridPoint, into: &gridPoint)
        c.decodeSetting(.gridSize, into: &gridSize)
        c.decodeSetting(.showName, into: &showName)
        c.decodeSetting(.showIcon, into: &showIcon)
        c.decodeSetting(.showColor, into: &showColor)
    }
}
