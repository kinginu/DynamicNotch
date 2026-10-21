// Settings of the System widget (Settings ▸ Nook ▸ Widgets ▸ System).
import SwiftUI

struct SystemStatsWidgetSettingsView: View {
    @StoredSetting(.systemStatsWidgetSettings) private var settings
    @State private var monitor = SystemStatsMonitor.shared

    var body: some View {
        SettingsForm {
            Section {
                ForEach(SystemStatsWidgetSettings.Row.allCases) { row in
                    Toggle(LocalizedStringKey(row.title), isOn: Binding(
                        get: { settings.rows.contains(row) },
                        set: { on in
                            if on { settings.rows.insert(row) } else { settings.rows.remove(row) }
                        }))
                }
                Toggle("Show efficiency and performance cores", isOn: $settings.showsClusters)
                    .disabled(!settings.rows.contains(.cpu))
            } header: {
                Text("Rows")
            }

            Section {
                SettingsChoicePicker("History", selection: $settings.historyMinutes,
                                     choices: SystemStatsWidgetSettings.historyChoices) { n in
                    Text("\(n) min")
                }
            } footer: {
                Text("Values are sampled every 2 seconds while the widget is in the Nook, also when the notch is closed. Only public system statistics are read (no helper, no SMC).")
                    .settingsFootnote()
            }

            if settings.rows.contains(.gpu), monitor.isRunning, !monitor.samples.isEmpty, monitor.gpuKey == nil {
                Section {
                    Text("This Mac does not report GPU utilisation in the I/O Registry.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
