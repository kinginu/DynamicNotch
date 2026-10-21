// Settings of the Media widget. Key "mediaWidgetSettings" (typed key still in
// Support/Ext-B.swift; pattern: SettingsUI/SettingsDecoding.swift): the grid size plus the
// `disabled` / `gridPoint` fields every widget setting carries.
import Foundation

struct MediaWidgetSettings: Preferences, WidgetPrefs, Codable, Equatable, Hashable {
    /// Stored grid size (2 × 1; the displayed width follows `NookWidgetLayout`).
    var size: NookGrid.Size = NookGrid.Size(width: .init(value: 2), height: .init(value: 1))
    // NotchView reads `.disabled` / `.gridPoint` on every widget settings value.
    var disabled: Bool = false
    var gridPoint: NookGrid.Point = NookGrid.Point(value: 0)

    private enum CodingKeys: String, CodingKey {
        case size, disabled, gridPoint
    }

    static let `default` = MediaWidgetSettings()

    var gridSizeType: NookWidget.NookGridSizeType { NookWidget.media.gridSizeType }
}

extension MediaWidgetSettings {
    // Tolerant decoding: a missing or undecodable field keeps its default.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.decodeSetting(.size, into: &size)
        c.decodeSetting(.disabled, into: &disabled)
        c.decodeSetting(.gridPoint, into: &gridPoint)
    }
}
