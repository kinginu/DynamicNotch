// Settings of the Network widget (2026-10-20). Key "networkWidgetSettings"
// (declared at the end of this file; pattern: SettingsUI/SettingsDecoding.swift).
import Foundation

struct NetworkWidgetSettings: Preferences, WidgetPrefs, Codable, Equatable, Hashable {
    /// Look up the public IPv4 address at api.ipify.org (off by default: it contacts a third party).
    var showsPublicIP: Bool = false
    /// Seconds between throughput samples.
    var samplingInterval: Int = 1
    /// Seconds of throughput history in the sparkline.
    var historySeconds: Int = 60
    /// BSD name of the interface to show (e.g. "en0"); nil = the primary interface.
    var interfaceName: String? = nil

    static let samplingIntervalChoices = [1, 2, 5]
    static let historySecondsChoices = [60, 120]

    static let `default` = NetworkWidgetSettings()

    var gridSizeType: NookWidget.NookGridSizeType { NookWidget.network.gridSizeType }

    init() {}

    // Tolerant decoding: a missing or undecodable field keeps its default.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.decodeSetting(.showsPublicIP, into: &showsPublicIP)
        c.decodeSetting(.samplingInterval, into: &samplingInterval)
        c.decodeSetting(.historySeconds, into: &historySeconds)
        c.decodeSetting(.interfaceName, into: &interfaceName)
        samplingInterval = max(1, samplingInterval)
    }

    private enum CodingKeys: String, CodingKey {
        case showsPublicIP, samplingInterval, historySeconds, interfaceName
    }
}

extension SettingKey {
    static let networkWidgetSettings = "networkWidgetSettings"
}

extension StoredKeys {
    static let networkWidgetSettings = Key<NetworkWidgetSettings>(SettingKey.networkWidgetSettings, default: .default)
}
