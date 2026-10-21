// Settings of the Usage widget (2026-10-20). Key: "usageWidgetSettings" (declared below;
// pattern: SettingsUI/SettingsDecoding.swift).
//
// Tracking is off by default (privacy): nothing is recorded until the user turns it on in
// Settings ▸ Nook ▸ Widgets ▸ Usage. When on, UsageTracker runs from launch whether or not the
// widget is in the Nook.
import Foundation

struct UsageWidgetSettings: Preferences, WidgetPrefs, Codable, Equatable, Hashable {
    /// Record which app is frontmost and for how long (local only).
    var trackingEnabled: Bool = false
    /// Seconds without keyboard / mouse / trackpad input after which the time stops counting.
    var idleThreshold: Int = 300
    /// Bundle identifiers that are never recorded (and hidden from what was recorded before).
    var excludedAppIDs: [String] = []

    static let idleThresholdChoices = [60, 120, 300, 600, 900]
    /// Daily totals older than this many days are deleted.
    static let retentionDays = 90

    static let `default` = UsageWidgetSettings()

    var gridSizeType: NookWidget.NookGridSizeType { NookWidget.usage.gridSizeType }

    init() {}

    // Tolerant decoding: a missing or undecodable field keeps its default.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.decodeSetting(.trackingEnabled, into: &trackingEnabled)
        c.decodeSetting(.idleThreshold, into: &idleThreshold)
        c.decodeSetting(.excludedAppIDs, into: &excludedAppIDs)
    }

    private enum CodingKeys: String, CodingKey {
        case trackingEnabled, idleThreshold, excludedAppIDs
    }

    var excludedSet: Set<String> { Set(excludedAppIDs) }
}

extension SettingKey {
    static let usageWidgetSettings = "usageWidgetSettings"
}

extension StoredKeys {
    static let usageWidgetSettings = Key<UsageWidgetSettings>(SettingKey.usageWidgetSettings, default: .default)
}
