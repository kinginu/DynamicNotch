// Settings ▸ Nook ▸ Widgets ▸ Notes (NotesWidgetSettings).
import SwiftUI

struct NotesWidgetSettingsView: View {
    @StoredSetting(.notesWidgetSettings) private var settings

    var body: some View {
        SettingsForm {
            Section {
                Toggle("Show date", isOn: $settings.showDate)
                Toggle("Show preview", isOn: $settings.showPreview)
            } footer: {
                Text("Click a note in the Nook to edit it in a window. Right-click a note to delete it.")
                    .settingsFootnote()
            }
        }
    }
}
