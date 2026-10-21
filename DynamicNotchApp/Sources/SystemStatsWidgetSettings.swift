// Settings of the System widget (NookWidget.systemStats, 2026-10-20).
//
// Key "systemStatsWidgetSettings" (name at the end of this file; typed key still in
// Support/Ext-C.swift; pattern: SettingsUI/SettingsDecoding.swift).
import Foundation

struct SystemStatsWidgetSettings: Preferences, WidgetPrefs, Codable, Equatable, Hashable {
    enum Row: String, Codable, CaseIterable, Identifiable, Hashable {
        case cpu, gpu, memory, disk, system
        var id: String { rawValue }

        var title: String {
            switch self {
            case .cpu: return "CPU"
            case .gpu: return "GPU"
            case .memory: return "Memory"
            case .disk: return "Disk"
            case .system: return "Thermal, Load & Uptime"
            }
        }
    }

    /// Rows shown, in the fixed order of `Row.allCases`.
    var rows: Set<Row> = Set(Row.allCases)
    /// CPU row: efficiency / performance cluster percentages under the total.
    var showsClusters: Bool = true
    /// Sparkline window in minutes (`historyChoices`).
    var historyMinutes: Int = 2

    static let historyChoices = [1, 2, 5]
    /// 5 grid cells (250 pt).
    static let cells: CGFloat = 5

    var visibleRows: [Row] { Row.allCases.filter(rows.contains) }
    var historySeconds: TimeInterval { TimeInterval(Self.historyChoices.contains(historyMinutes) ? historyMinutes : 2) * 60 }

    static let `default` = SystemStatsWidgetSettings()

    var gridSizeType: NookWidget.NookGridSizeType { .doubleWide }

    init() {}

    // Tolerant decoding: a missing or undecodable field keeps its default; unknown row names are
    // dropped (rows are stored by name so a later version's rows do not fail the list).
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var names: [String] = visibleRows.map(\.rawValue)
        c.decodeSetting(.rows, into: &names)
        rows = Set(names.compactMap(Row.init(rawValue:)))
        c.decodeSetting(.showsClusters, into: &showsClusters)
        c.decodeSetting(.historyMinutes, into: &historyMinutes)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(visibleRows.map(\.rawValue), forKey: .rows)
        try c.encode(showsClusters, forKey: .showsClusters)
        try c.encode(historyMinutes, forKey: .historyMinutes)
    }

    private enum CodingKeys: String, CodingKey {
        case rows, showsClusters, historyMinutes
    }
}

extension SettingKey {
    static let systemStatsWidgetSettings = "systemStatsWidgetSettings"
}
