// Settings of the Displays widget (2026-10-20). Key "displaysWidgetSettings"
// (declared at the end of this file; pattern: SettingsUI/SettingsDecoding.swift).
import Foundation

struct DisplaysWidgetSettings: Preferences, WidgetPrefs, Codable, Equatable, Hashable {
    /// DisplayInfo.key of the displays the user turned off (a hide-list, so a newly connected
    /// display appears without visiting the settings).
    var disabledDisplays: [String] = []
    /// Talk to external monitors over DDC/CI (I2C). Off: externals are listed without controls.
    var ddcEnabled: Bool = true
    var showContrast: Bool = false
    /// Only for monitors whose capabilities string advertises VCP 0x62.
    var showVolume: Bool = true
    /// Current input (read-only).
    var showInputSource: Bool = true
    /// Seconds between DDC/CI reads (the built-in display is read every 2 s).
    var refreshInterval: Int = 30

    static let `default` = DisplaysWidgetSettings()
    static let refreshIntervalChoices = [15, 30, 60, 300]

    var gridSizeType: NookWidget.NookGridSizeType { .small }   // width: DisplaysWidgetLayout (5 cells)

    init() {}

    // Tolerant decoding: a missing or undecodable field keeps its default.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.decodeSetting(.disabledDisplays, into: &disabledDisplays)
        c.decodeSetting(.ddcEnabled, into: &ddcEnabled)
        c.decodeSetting(.showContrast, into: &showContrast)
        c.decodeSetting(.showVolume, into: &showVolume)
        c.decodeSetting(.showInputSource, into: &showInputSource)
        c.decodeSetting(.refreshInterval, into: &refreshInterval)
    }

    private enum CodingKeys: String, CodingKey {
        case disabledDisplays, ddcEnabled, showContrast, showVolume, showInputSource, refreshInterval
    }

    func isEnabled(_ display: DisplayInfo) -> Bool { !disabledDisplays.contains(display.key) }

    mutating func setEnabled(_ enabled: Bool, _ display: DisplayInfo) {
        disabledDisplays.removeAll { $0 == display.key }
        if !enabled { disabledDisplays.append(display.key) }
    }

    /// The displays the widget shows, in the service's order.
    func visible(_ displays: [DisplayInfo]) -> [DisplayInfo] { displays.filter(isEnabled) }
}

extension SettingKey {
    static let displaysWidgetSettings = "displaysWidgetSettings"
}

extension StoredKeys {
    static let displaysWidgetSettings = Key<DisplaysWidgetSettings>(SettingKey.displaysWidgetSettings, default: .default)
}
