// Settings of the calendar live activity (Live Activities ▸ Customize): a form over
//   CalendarLiveActivitySettings.
import SwiftUI

struct CalendarLiveActivitySettingsView: View {
    @StoredSetting(.calendarLiveActivitySettings) private var settings: CalendarLiveActivitySettings

    var body: some View {
        SettingsForm {
            Section {
                Toggle("Enabled", isOn: $settings.isEnabled)
                Picker("Appearance", selection: $settings.appearanceMode) {
                    Text("Constant").tag(CalendarLiveActivitySettings.AppearanceMode.constant)
                    Text("Periodic").tag(CalendarLiveActivitySettings.AppearanceMode.periodic)
                }
                // the closed-notch activity uses minutesBefore; daysAhead / maxEventCount /
                // showAllDayEvents are kept in the stored settings but unused by the activity
                Stepper("Show \(settings.minutesBefore) min before the event", value: $settings.minutesBefore, in: 1...60)
            } footer: {
                Text("Requires Calendar access (System Settings ▸ Privacy & Security ▸ Calendars).")
                    .settingsFootnote()
            }
        }
    }
}
