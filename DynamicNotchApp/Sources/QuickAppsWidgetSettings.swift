// Settings of the Quick Apps widget. Key "quickAppsWidgetSettings" (typed key still
// in Support/Ext-C.swift; pattern: SettingsUI/SettingsDecoding.swift). The pinned apps themselves
// are a separate key (`quickAppsPaths`, Support/Ext-A.swift).
import Foundation

struct QuickAppsWidgetSettings: Preferences, WidgetPrefs, Codable, Equatable, Hashable {
    // NotchView reads `.disabled` / `.gridPoint` on every widget settings value.
    var disabled: Bool = false
    var gridPoint: NookGrid.Point = NookGrid.Point(value: 0)
    /// Stored grid size (kept for stored-value compatibility).
    var gridSize: NookGrid.Size = NookGrid.Size(width: .init(value: 1), height: .init(value: 1))
    /// Show the app names under the icons.
    var showAppNames: Bool = true
    /// Show the app icons (unused).
    var showAppIcons: Bool = true
    /// Most apps shown (unused).
    var maxAppCount: Int = 8

    private enum CodingKeys: String, CodingKey {
        case disabled, gridPoint, gridSize, showAppNames, showAppIcons, maxAppCount
    }

    static let `default` = QuickAppsWidgetSettings()

    var gridSizeType: NookWidget.NookGridSizeType { NookWidget.quickApps.gridSizeType }
}

extension QuickAppsWidgetSettings {
    // Tolerant decoding: a missing or undecodable field keeps its default.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.decodeSetting(.disabled, into: &disabled)
        c.decodeSetting(.gridPoint, into: &gridPoint)
        c.decodeSetting(.gridSize, into: &gridSize)
        c.decodeSetting(.showAppNames, into: &showAppNames)
        c.decodeSetting(.showAppIcons, into: &showAppIcons)
        c.decodeSetting(.maxAppCount, into: &maxAppCount)
    }
}
