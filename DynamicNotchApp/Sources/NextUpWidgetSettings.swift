// Settings of the Next Up widget (2026-10-20). Key "nextUpWidgetSettings"
// (declared at the end of this file; pattern: SettingsUI/SettingsDecoding.swift).
import Foundation

struct NextUpWidgetSettings: Preferences, WidgetPrefs, Codable, Equatable, Hashable {
    /// How far ahead the widget looks for events (hours).
    var lookaheadHours: Int = 12
    /// Number of events shown (1–3).
    var maxEvents: Int = 3
    /// Calendars left out (empty = every calendar; calendars added later are included).
    var excludedCalendarIDs: [String] = []
    /// Show all-day events (they never trigger the closed-notch activity).
    var includeAllDay: Bool = false
    /// Show the closed-notch live activity before an event starts.
    var showLiveActivity: Bool = true
    /// Minutes before the start at which the live activity appears.
    var leadMinutes: Int = 5

    static let lookaheadChoices = [1, 3, 6, 12, 24, 48]
    static let leadChoices = [1, 2, 5, 10, 15, 30]

    static let `default` = NextUpWidgetSettings()

    var gridSizeType: NookWidget.NookGridSizeType { NookWidget.nextUp.gridSizeType }

    init() {}

    // Tolerant decoding: a missing or undecodable field keeps its default.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.decodeSetting(.lookaheadHours, into: &lookaheadHours)
        c.decodeSetting(.maxEvents, into: &maxEvents)
        c.decodeSetting(.excludedCalendarIDs, into: &excludedCalendarIDs)
        c.decodeSetting(.includeAllDay, into: &includeAllDay)
        c.decodeSetting(.showLiveActivity, into: &showLiveActivity)
        c.decodeSetting(.leadMinutes, into: &leadMinutes)
        maxEvents = min(3, max(1, maxEvents))
    }

    private enum CodingKeys: String, CodingKey {
        case lookaheadHours, maxEvents, excludedCalendarIDs, includeAllDay, showLiveActivity, leadMinutes
    }
}

extension SettingKey {
    static let nextUpWidgetSettings = "nextUpWidgetSettings"
}

extension StoredKeys {
    static let nextUpWidgetSettings = Key<NextUpWidgetSettings>(SettingKey.nextUpWidgetSettings, default: .default)
}
