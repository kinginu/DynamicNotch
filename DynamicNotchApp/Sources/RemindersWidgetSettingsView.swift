// Settings ▸ Nook ▸ Widgets ▸ Reminders (2026-10-20). Replaces
// TodoListWidgetSettingsView. Access state, the Reminders lists to show (none chosen = the
// default list), the list new reminders go to, and the due date toggle.
import SwiftUI
import EventKit

struct RemindersWidgetSettingsView: View {
    @StoredSetting(.remindersWidgetSettings) private var settings

    private var manager: RemindersManager { RemindersManager.shared }

    var body: some View {
        SettingsForm {
            if !manager.hasAccess {
                Section {
                    PermissionStatusRow(
                        kind: .reminders,
                        status: PermissionStatus(manager.authorizationStatus),
                        notDetermined: "DynamicNotch needs access to Reminders to show and add your reminders.",
                        denied: "Reminders access is off. Turn on DynamicNotch in System Settings ▸ Privacy & Security ▸ Reminders.",
                        allowTitle: "Allow Access",
                        allow: { Task { await manager.requestAccess() } })
                }
            } else {
                Section {
                    ForEach(manager.lists) { list in
                        Toggle(isOn: binding(for: list)) {
                            SettingsCalendarLabel(color: list.color.color, title: list.title, source: list.sourceTitle)
                        }
                    }
                } header: {
                    Text("Lists")
                } footer: {
                    Text("When no list is chosen, the widget shows your default Reminders list.")
                        .settingsFootnote()
                }

                if manager.shownLists.count > 1 {
                    Section {
                        Picker("Add new reminders to", selection: newListBinding) {
                            ForEach(manager.shownLists) { list in
                                Text(list.title).tag(Optional(list.id))
                            }
                        }
                    }
                }

                Section {
                    Toggle("Show due dates", isOn: $settings.showDueDates)
                } footer: {
                    Text("The widget shows incomplete reminders, sorted by due date. Lists, due dates and details are edited in Reminders.")
                        .settingsFootnote()
                }
            }
        }
        .onAppear { manager.reload() }
        .onChange(of: settings.listIdentifiers) { _, _ in manager.reload() }
    }

    /// A list is "on" when it is chosen, or — with nothing chosen — when it is the shown default.
    private func binding(for list: ReminderList) -> Binding<Bool> {
        Binding(
            get: {
                settings.listIdentifiers.isEmpty
                    ? manager.shownLists.contains { $0.id == list.id }
                    : settings.listIdentifiers.contains(list.id)
            },
            set: { on in
                var ids = settings.listIdentifiers.isEmpty ? manager.shownLists.map(\.id) : settings.listIdentifiers
                if on {
                    if !ids.contains(list.id) { ids.append(list.id) }
                } else {
                    ids.removeAll { $0 == list.id }
                }
                // keep the stored order in the order of the list of lists
                let order = manager.lists.map(\.id)
                settings.listIdentifiers = ids.filter(order.contains)
                    .sorted { (order.firstIndex(of: $0) ?? 0) < (order.firstIndex(of: $1) ?? 0) }
            }
        )
    }

    private var newListBinding: Binding<String?> {
        Binding(
            get: { manager.targetList?.id },
            set: { settings.newReminderListIdentifier = $0 }
        )
    }
}
