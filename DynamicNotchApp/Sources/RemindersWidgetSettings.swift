// Settings of the Reminders widget (Apple Reminders via EventKit, 2026-10-20).
// Replaces TodoListWidgetSettings (the in-app to-do list was discarded, no migration).
// Key "remindersWidgetSettings" (typed key still in Support/Ext-C.swift; pattern: SettingsUI/SettingsDecoding.swift).
import Foundation

struct RemindersWidgetSettings: Preferences, WidgetPrefs, Codable, Equatable, Hashable {

    // NotchView reads `.disabled` / `.gridPoint` on every widget settings value
    var disabled: Bool = false
    var gridPoint: NookGrid.Point = NookGrid.Point(value: 0)

    // WidgetPrefs: grid size type follows the widget case
    static let `default` = RemindersWidgetSettings()

    var gridSizeType: NookWidget.NookGridSizeType { NookWidget.reminders.gridSizeType }

    /// `calendarIdentifier`s of the Reminders lists shown, in this order. Empty = the default
    /// list for new reminders (Reminders ▸ Settings ▸ Default List).
    var listIdentifiers: [String] = []

    /// List that new reminders are added to, when several lists are shown (nil or no longer
    /// shown = the first shown list).
    var newReminderListIdentifier: String? = nil

    /// Show the due date under each reminder.
    var showDueDates: Bool = true

    init() {}

    // Tolerant decoding: a missing or undecodable field keeps its default.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.decodeSetting(.disabled, into: &disabled)
        c.decodeSetting(.gridPoint, into: &gridPoint)
        c.decodeSetting(.listIdentifiers, into: &listIdentifiers)
        c.decodeSetting(.newReminderListIdentifier, into: &newReminderListIdentifier)
        c.decodeSetting(.showDueDates, into: &showDueDates)
    }

    private enum CodingKeys: String, CodingKey {
        case disabled, gridPoint, listIdentifiers, newReminderListIdentifier, showDueDates
    }
}
