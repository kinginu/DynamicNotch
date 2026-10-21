// Settings of the Clipboard history widget (Settings ▸ Nook ▸ Widgets ▸ Clipboard).
import SwiftUI

struct ClipboardWidgetSettingsView: View {
    @StoredSetting(.clipboardWidgetSettings) private var settings
    @State private var manager = ClipboardHistoryManager.shared
    @State private var confirmingClear = false

    var body: some View {
        SettingsForm {
            Section {
                Toggle("Record clipboard history", isOn: $settings.isRecording)
                SettingsChoicePicker("History size", selection: $settings.historyLimit,
                                     choices: ClipboardWidgetSettings.historyLimitChoices) { n in
                    Text("\(n) items")
                }
                Toggle("Save images", isOn: $settings.captureImages)
                Toggle("Save copied files", isOn: $settings.captureFiles)
            } footer: {
                Text("History is kept only on this Mac (Application Support). Items that password managers mark as concealed are never recorded.")
                    .settingsFootnote()
            }

            Section {
                if settings.excludedBundleIDs.isEmpty {
                    Text("No excluded apps")
                        .foregroundStyle(.secondary)
                }
                ForEach(settings.excludedBundleIDs, id: \.self) { bundleID in
                    HStack(spacing: 8) {
                        SettingsAppIcon(bundleID: bundleID)
                        Text(SettingsApps.name(of: bundleID))
                        Spacer()
                        SettingsRemoveButton { settings.excludedBundleIDs.removeAll { $0 == bundleID } }
                    }
                }
                Button("Add App…", action: addApps)
            } header: {
                Text("Excluded apps")
            } footer: {
                Text("Copies made while one of these apps is in front are not recorded.")
                    .settingsFootnote()
            }

            Section {
                SettingsHistoryRow(
                    summary: manager.items.count == 1
                        ? String(localized: "1 item in history")
                        : String(localized: "\(manager.items.count) items in history"),
                    clearTitle: "Clear History…",
                    isEmpty: manager.items.isEmpty,
                    clear: { confirmingClear = true })
            }
        }
        .onAppear { manager.start() }
        .confirmationDialog("Clear clipboard history?", isPresented: $confirmingClear) {
            Button("Clear History", role: .destructive) { manager.clear() }
        } message: {
            Text("This removes all saved items. It cannot be undone.")
        }
    }

    private func addApps() {
        for id in SettingsApps.chooseBundleIDs() where !settings.excludedBundleIDs.contains(id) {
            settings.excludedBundleIDs.append(id)
        }
    }
}
