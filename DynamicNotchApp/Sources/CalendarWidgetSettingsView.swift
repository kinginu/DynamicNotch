// Settings ▸ Nook ▸ Widgets ▸ Calendar: calendar access, the calendars the widget
// shows (CalendarManager's selection, persisted as `UserDefaults.calendarWidgetSettings`) and the
// all-day toggle.
import SwiftUI
import EventKit

struct CalendarWidgetSettingsView: View {
    @State private var allCalendars: [EKCalendar] = []
    @State private var selectedCalendars: Set<String> = []
    @State private var showAllDayEvents: Bool = UserDefaults.standard.calendarWidgetSettings.showAllDayEvents

    var body: some View {
        let manager = CalendarManager.shared
        SettingsForm {
            if !manager.hasReadAccess {
                Section {
                    PermissionStatusRow.calendars(status: manager.authorizationStatus) {
                        Task { await manager.requestFullAccess(); loadCalendars() }
                    }
                }
            } else {
                Section {
                    ForEach(allCalendars, id: \.calendarIdentifier) { cal in
                        Toggle(isOn: binding(for: cal.calendarIdentifier)) {
                            SettingsCalendarLabel(color: Color(cgColor: cal.cgColor), title: cal.title,
                                                  source: cal.source?.title ?? "")
                        }
                    }
                } header: {
                    SettingsSectionHeader("Calendars") {
                        Button("Select All") { setSelection(Set(allCalendars.map(\.calendarIdentifier))) }
                    }
                }
                Section {
                    Toggle("Show all-day events", isOn: $showAllDayEvents)
                        .onChange(of: showAllDayEvents) { _, value in
                            var settings = UserDefaults.standard.calendarWidgetSettings
                            settings.showAllDayEvents = value
                            UserDefaults.standard.calendarWidgetSettings = settings
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
            get: { selectedCalendars.contains(id) },
            set: { on in
                var selection = selectedCalendars
                if on { selection.insert(id) } else { selection.remove(id) }
                setSelection(selection)
            }
        )
    }

    private func loadCalendars() {
        let manager = CalendarManager.shared
        guard manager.hasReadAccess else { return }
        allCalendars = manager.eventStore.calendars(for: .event)
            .sorted { ($0.source?.title ?? "", $0.title) < ($1.source?.title ?? "", $1.title) }
        // empty = all calendars, unless the user deselected every calendar (then none is on)
        let selected = manager.selectedCalendars.isEmpty && !manager.selectionIsExplicitlyEmpty
            ? allCalendars : manager.selectedCalendars
        selectedCalendars = Set(selected.map(\.calendarIdentifier))
    }

    /// Selects the calendars with these identifiers (in the order of the list) and saves them.
    private func setSelection(_ ids: Set<String>) {
        selectedCalendars = ids
        CalendarManager.shared.updateSelectedCalendars(allCalendars.filter { ids.contains($0.calendarIdentifier) })
    }
}

extension PermissionStatusRow {
    /// Calendar access row of the Calendar and Next Up panes (shown only while access is missing).
    static func calendars(status: EKAuthorizationStatus, allow: @escaping () -> Void) -> PermissionStatusRow {
        PermissionStatusRow(
            kind: .calendar,
            status: PermissionStatus(status),
            notDetermined: "DynamicNotch needs access to your calendars to show events.",
            denied: "Calendar access is off. Turn on DynamicNotch in System Settings ▸ Privacy & Security ▸ Calendars.",
            allowTitle: "Allow Access",
            allow: allow)
    }
}
