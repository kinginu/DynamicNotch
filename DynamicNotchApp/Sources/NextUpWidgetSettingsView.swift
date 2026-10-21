// Settings ▸ Nook ▸ Widgets ▸ Next Up (2026-10-20): lookahead window, number of events,
// all-day events, calendars to include, and the closed-notch reminder with its lead time.
import SwiftUI
import EventKit

struct NextUpWidgetSettingsView: View {
    @StoredSetting(.nextUpWidgetSettings) private var settings
    @State private var calendars: [EKCalendar] = []

    var body: some View {
        let manager = CalendarManager.shared
        SettingsForm {
            Section {
                SettingsChoicePicker("Look ahead", selection: $settings.lookaheadHours,
                                     choices: NextUpWidgetSettings.lookaheadChoices) { h in
                    Text(Duration.seconds(h * 3600), format: .units(allowed: [.hours], width: .wide))
                }
                Picker("Events shown", selection: $settings.maxEvents) {
                    ForEach(1...3, id: \.self) { n in Text(n, format: .number).tag(n) }
                }
                Toggle("Show all-day events", isOn: $settings.includeAllDay)
            }

            Section {
                Toggle("Remind in the closed notch", isOn: $settings.showLiveActivity)
                SettingsChoicePicker("Show the reminder", selection: $settings.leadMinutes,
                                     choices: NextUpWidgetSettings.leadChoices) { m in
                    Text("\(m) min before")
                }
                .disabled(!settings.showLiveActivity)
            } footer: {
                Text("The closed notch shows a calendar symbol and the minutes left until the event starts. Dismiss it with the bell button in the widget.")
                    .settingsFootnote()
            }

            if !manager.hasReadAccess {
                Section {
                    PermissionStatusRow.calendars(status: manager.authorizationStatus) {
                        Task { await manager.requestFullAccess(); loadCalendars(); NextUpManager.shared.refresh() }
                    }
                }
            } else {
                Section {
                    ForEach(calendars, id: \.calendarIdentifier) { cal in
                        Toggle(isOn: binding(for: cal.calendarIdentifier)) {
                            SettingsCalendarLabel(color: Color(cgColor: cal.cgColor), title: cal.title,
                                                  source: cal.source?.title ?? "")
                        }
                    }
                } header: {
                    SettingsSectionHeader("Calendars") {
                        Button("Select All") { settings.excludedCalendarIDs = [] }
                            .disabled(settings.excludedCalendarIDs.isEmpty)
                    }
                }
            }
        }
        .onAppear {
            manager.refreshAuthorizationStatus()
            loadCalendars()
        }
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { !settings.excludedCalendarIDs.contains(id) },
            set: { on in
                var excluded = settings.excludedCalendarIDs.filter { $0 != id }
                if !on { excluded.append(id) }
                settings.excludedCalendarIDs = excluded.sorted()
            }
        )
    }

    private func loadCalendars() {
        let manager = CalendarManager.shared
        guard manager.hasReadAccess else { return }
        calendars = manager.eventStore.calendars(for: .event)
            .sorted { ($0.source?.title ?? "", $0.title) < ($1.source?.title ?? "", $1.title) }
    }
}
