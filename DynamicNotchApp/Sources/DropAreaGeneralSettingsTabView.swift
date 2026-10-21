// Settings ▸ Nook ▸ Drop Area. Wording is our own (2026-10-20); the
//   "pipelines" placeholder section was removed (not implemented).
import SwiftUI

struct DropAreaGeneralSettingsTabView: View {
    @StoredSetting(.dropAreaSettings) private var settings

    var body: some View {
        SettingsForm {
            Section {
                Toggle("Enable drop area", isOn: $settings.enabled)
            } header: {
                Text("Drop Area")
            } footer: {
                Text("Drop files on the notch to keep them in the tray or send them with AirDrop.")
                    .settingsFootnote()
            }

            Section {
                LabeledContent("Tray") {
                    Text("Always on")
                        .foregroundStyle(.secondary)
                }
                Toggle("AirDrop", isOn: $settings.showAirDropTarget)
            } header: {
                Text("Targets")
            } footer: {
                Text("Shows an AirDrop area on the right side of the tray. Drop files on it, from Finder or from the tray, to send them via AirDrop.")
                    .settingsFootnote()
            }
            .disabled(!settings.enabled)
        }
    }
}
