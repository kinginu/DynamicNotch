// Settings of the Calendar widget. Key "calendarWidgetSettings" (typed key still in
// Support/Ext-C.swift; pattern: SettingsUI/SettingsDecoding.swift). The calendar selection and the
// all-day toggle the widget uses are stored separately (`UserDefaults.calendarWidgetSettings`,
// CalendarManager); the fields below are kept so stored values keep decoding and re-encoding.
import Foundation

struct CalendarWidgetSettings: Preferences, WidgetPrefs, Codable, Equatable, Hashable {
    // NotchView reads `.disabled` / `.gridPoint` on every widget settings value.
    var disabled: Bool = false
    var gridPoint: NookGrid.Point = NookGrid.Point(value: 0)
    /// Whether the widget is enabled.
    var enabled: Bool = true
    /// Display mode ("month").
    var displayMode: String = "month"
    /// Dots under days with events.
    var showEventDots: Bool = true
    /// Highlight Saturdays and Sundays.
    var highlightWeekends: Bool = true
    /// First day of the week (1 = Sunday, 2 = Monday).
    var firstWeekday: Int = 1

    private enum CodingKeys: String, CodingKey {
        case disabled, gridPoint, enabled, displayMode, showEventDots, highlightWeekends, firstWeekday
    }

    static let `default` = CalendarWidgetSettings()

    var gridSizeType: NookWidget.NookGridSizeType { NookWidget.calendar.gridSizeType }
}

extension CalendarWidgetSettings {
    // Tolerant decoding: a missing or undecodable field keeps its default. (In an extension, so
    // the implicit memberwise initializer stays.)
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.decodeSetting(.disabled, into: &disabled)
        c.decodeSetting(.gridPoint, into: &gridPoint)
        c.decodeSetting(.enabled, into: &enabled)
        c.decodeSetting(.displayMode, into: &displayMode)
        c.decodeSetting(.showEventDots, into: &showEventDots)
        c.decodeSetting(.highlightWeekends, into: &highlightWeekends)
        c.decodeSetting(.firstWeekday, into: &firstWeekday)
    }
}
