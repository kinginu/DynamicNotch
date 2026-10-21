// Settings of the World Clock widget (2026-10-20). Key "worldClocksWidgetSettings"
// (declared at the end of this file; pattern: SettingsUI/SettingsDecoding.swift).
//
// A row of city tiles like the macOS World Clock widget: short label (TOK, CUP, NY …), large time,
// day + hour difference from this Mac, light tile in local daytime / dark at night, optional
// analog mini-dial. The widget grows by one tile per clock (WorldClockWidgetLayout).
import Foundation

/// One clock of the widget.
struct WorldClock: Codable, Hashable, Identifiable {
    /// `timeZoneID` of the clock that follows this Mac's current time zone.
    static let localID = "local"

    var id: UUID = UUID()
    /// A `TimeZone.knownTimeZoneIdentifiers` entry, or `WorldClock.localID`.
    var timeZoneID: String
    /// User label ("Cupertino", "HQ" …); empty = the city of the time zone.
    var label: String = ""

    init(timeZoneID: String, label: String = "") {
        self.timeZoneID = timeZoneID
        self.label = label
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        timeZoneID = try c.decodeIfPresent(String.self, forKey: .timeZoneID) ?? Self.localID
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
    }

    private enum CodingKeys: String, CodingKey { case id, timeZoneID, label }

    var isLocal: Bool { timeZoneID == Self.localID }

    /// The zone the clock shows (an unknown stored identifier falls back to this Mac's zone).
    var timeZone: TimeZone {
        isLocal ? .current : (TimeZone(identifier: timeZoneID) ?? .current)
    }

    /// Full name: the label, else the city of the zone ("America/Los_Angeles" → "Los Angeles").
    var displayName: String {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        return Self.cityName(of: timeZone.identifier)
    }

    /// Tile label: a short label as typed (≤ 4 characters), else an abbreviation of the name —
    /// initials of a multi-word name ("New York" → "NY"), the first three letters otherwise
    /// ("Tokyo" → "TOK", "Cupertino" → "CUP").
    var shortLabel: String {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, trimmed.count <= 4 { return trimmed.uppercased() }
        return Self.abbreviation(of: displayName)
    }

    static func cityName(of identifier: String) -> String {
        if identifier == "GMT" || identifier == "UTC" { return identifier }
        let last = identifier.split(separator: "/").last.map(String.init) ?? identifier
        return last.replacingOccurrences(of: "_", with: " ")
    }

    static func abbreviation(of name: String) -> String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "-" }).filter { !$0.isEmpty }
        if words.count >= 2 {
            return String(words.prefix(3).compactMap { $0.first }).uppercased()
        }
        return String(name.filter { $0.isLetter || $0.isNumber }.prefix(3)).uppercased()
    }
}

struct WorldClockWidgetSettings: Preferences, WidgetPrefs, Codable, Equatable, Hashable {
    enum HourFormat: String, Codable, CaseIterable, Hashable {
        /// Follow the system locale / Language & Region setting.
        case system
        case twelveHour
        case twentyFourHour
    }

    var clocks: [WorldClock] = WorldClockWidgetSettings.defaultClocks()
    var showSeconds: Bool = false
    var hourFormat: HourFormat = .system
    /// Small analog dial above the digital time.
    var showAnalogDial: Bool = false
    /// Light tile while it is daytime in that city, dark at night (else every tile is dark).
    var tintByDaytime: Bool = true

    /// Most clocks the widget holds (beyond ~6 the Nook row scrolls).
    static let maxClocks = 8

    /// This Mac + Tokyo, Cupertino, New York, London (zones equal to this Mac's are skipped).
    static func defaultClocks() -> [WorldClock] {
        let local = TimeZone.current.identifier
        let others = [
            WorldClock(timeZoneID: "Asia/Tokyo"),
            WorldClock(timeZoneID: "America/Los_Angeles", label: "Cupertino"),
            WorldClock(timeZoneID: "America/New_York"),
            WorldClock(timeZoneID: "Europe/London"),
        ].filter { $0.timeZoneID != local }
        return [WorldClock(timeZoneID: WorldClock.localID)] + others
    }

    static let `default` = WorldClockWidgetSettings()

    var gridSizeType: NookWidget.NookGridSizeType { NookWidget.worldClocks.gridSizeType }

    init() {}

    // Tolerant decoding: a missing or undecodable field keeps its default.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.decodeSetting(.clocks, into: &clocks)
        c.decodeSetting(.showSeconds, into: &showSeconds)
        c.decodeSetting(.hourFormat, into: &hourFormat)
        c.decodeSetting(.showAnalogDial, into: &showAnalogDial)
        c.decodeSetting(.tintByDaytime, into: &tintByDaytime)
    }

    private enum CodingKeys: String, CodingKey {
        case clocks, showSeconds, hourFormat, showAnalogDial, tintByDaytime
    }

    /// Whether times use a 12-hour clock with AM/PM.
    var usesTwelveHourClock: Bool {
        switch hourFormat {
        case .twelveHour: return true
        case .twentyFourHour: return false
        case .system:
            let pattern = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .autoupdatingCurrent) ?? "HH"
            // drop quoted literals first: fr_FR gives "HH 'h'", de_DE "HH 'Uhr'" (24-hour)
            let symbols = pattern.replacingOccurrences(of: "'[^']*'", with: "", options: .regularExpression)
            return symbols.contains("a") || symbols.contains("h") || symbols.contains("K")
        }
    }
}

extension SettingKey {
    static let worldClocksWidgetSettings = "worldClocksWidgetSettings"
}

extension StoredKeys {
    static let worldClocksWidgetSettings = Key<WorldClockWidgetSettings>(SettingKey.worldClocksWidgetSettings, default: .default)
}

// MARK: - Layout (one tile per clock)

enum WorldClockWidgetLayout {
    static let tileWidth: CGFloat = 84
    /// Wider tiles when seconds are shown ("18:23:45").
    static let tileWidthWithSeconds: CGFloat = 104
    static let tileSpacing: CGFloat = 6

    static func tileWidth(showSeconds: Bool) -> CGFloat {
        showSeconds ? tileWidthWithSeconds : tileWidth
    }

    /// Widget width for `count` clocks (empty state: 3 cells).
    static func width(count: Int, showSeconds: Bool) -> CGFloat {
        guard count > 0 else { return 150 }
        let n = CGFloat(count)
        return 2 * NookWidgetMetrics.padding + n * tileWidth(showSeconds: showSeconds) + (n - 1) * tileSpacing
    }

    /// Grid cells (fractional, like the Mirror widget) for NookWidgetLayout.cells(of: .worldClocks).
    /// Reads the settings through the store's Observation tracking, so the Nook row re-lays out
    /// when clocks are added or removed.
    static func preferredCells() -> CGFloat {
        let settings = SettingsStore.shared.observedValue(.worldClocksWidgetSettings)
        return width(count: settings.clocks.count, showSeconds: settings.showSeconds) / NookWidgetLayout.cell
    }
}
