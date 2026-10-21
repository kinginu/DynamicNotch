// Settings of the Batteries widget (2026-10-20). Key: "batteriesWidgetSettings" (declared
// below; pattern: SettingsUI/SettingsDecoding.swift).
import Foundation

struct BatteriesWidgetSettings: Preferences, WidgetPrefs, Codable, Equatable, Hashable {
    /// Show this Mac's own battery (first row).
    var showThisMac: Bool = true
    /// Hide accessories whose level is below this percentage (nil = show all). This Mac follows
    /// `showThisMac` only.
    var hideBelowPercent: Int? = nil
    /// Seconds between refreshes (power-source and Bluetooth events refresh immediately as well).
    var refreshInterval: Int = 30

    static let hideBelowChoices = [5, 10, 20, 50]
    static let refreshIntervalChoices = [15, 30, 60, 300]

    static let `default` = BatteriesWidgetSettings()

    var gridSizeType: NookWidget.NookGridSizeType { NookWidget.batteries.gridSizeType }

    init() {}

    // Tolerant decoding: a missing or undecodable field keeps its default.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.decodeSetting(.showThisMac, into: &showThisMac)
        c.decodeSetting(.hideBelowPercent, into: &hideBelowPercent)
        c.decodeSetting(.refreshInterval, into: &refreshInterval)
    }

    private enum CodingKeys: String, CodingKey {
        case showThisMac, hideBelowPercent, refreshInterval
    }

    /// The devices the widget shows, in the manager's order.
    func visible(_ devices: [BatteryDevice]) -> [BatteryDevice] {
        devices.filter { device in
            if device.isThisMac { return showThisMac }
            if let limit = hideBelowPercent { return device.percent >= limit }
            return true
        }
    }
}

extension SettingKey {
    static let batteriesWidgetSettings = "batteriesWidgetSettings"
}

extension StoredKeys {
    static let batteriesWidgetSettings = Key<BatteriesWidgetSettings>(SettingKey.batteriesWidgetSettings, default: .default)
}
