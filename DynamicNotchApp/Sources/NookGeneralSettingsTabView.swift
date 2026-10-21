// Settings ▸ Nook ▸ General: the
//   widgets in the Nook and the layout options of NookSettings (widget order lives in the Widgets tab).
import SwiftUI
struct NookGeneralSettingsTabView: View {
    @StoredSetting(.nookSettings) private var nookSettings

    var body: some View {
        SettingsForm {
            Section {
                LabeledContent("Widgets") {
                    Text(nookSettings.widgets.isEmpty
                         ? String(localized: "None")
                         : nookSettings.widgets.map { String(localized: String.LocalizationValue($0.name)) }.joined(separator: ", "))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                Button("Choose Widgets…") {
                    NookSettingsNavigation.shared.tab = .widgets
                }
            } header: {
                Text("Nook")
            }
            Section {
                Slider(value: $nookSettings.separatorSpacing, in: 0...24, step: 2) {
                    Text("Space between widgets")
                }
            } header: {
                Text("Layout")
            } footer: {
                Text("Extra space on each side of the separator between two widgets.")
                    .settingsFootnote()
            }
        }
    }
}
