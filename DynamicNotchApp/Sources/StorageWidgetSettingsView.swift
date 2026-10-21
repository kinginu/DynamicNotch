// Settings ▸ Nook ▸ Widgets ▸ Storage (2026-10-20): GB or percent, disk images on/off, and
// which of the mounted volumes the widget shows.
import SwiftUI

struct StorageWidgetSettingsView: View {
    @StoredSetting(.storageWidgetSettings) private var settings
    @State private var manager = StorageVolumesManager.shared

    var body: some View {
        SettingsForm {
            Section {
                Picker("Show", selection: $settings.displayMode) {
                    Text("Free space (GB)").tag(StorageDisplayMode.gigabytes)
                    Text("Percentage used").tag(StorageDisplayMode.percent)
                }
                Toggle("Show disk images", isOn: $settings.showDiskImages)
            } footer: {
                Text("Updates every minute and whenever a disk is mounted or ejected.")
                    .settingsFootnote()
            }

            Section {
                if manager.volumes.isEmpty {
                    Text("No volumes").foregroundStyle(.secondary)
                }
                ForEach(manager.volumes) { v in
                    Toggle(isOn: binding(for: v)) {
                        SettingsSymbolRow(systemImage: v.kind.systemImage) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(v.name)
                                Text(StorageAccessibility.summary(v))
                                    .monospacedDigit()
                                    .settingsFootnote()
                            }
                        }
                    }
                    .disabled(v.kind == .diskImage && !settings.showDiskImages)
                }
            } header: {
                Text("Volumes")
            } footer: {
                Text("New disks are shown automatically.")
                    .settingsFootnote()
            }
        }
        .onAppear { manager.setVisible(true) }
        .onDisappear { manager.setVisible(false) }
    }

    private func binding(for v: StorageVolume) -> Binding<Bool> {
        Binding(
            get: { !settings.hiddenVolumeIDs.contains(v.id) },
            set: { show in
                if show { settings.hiddenVolumeIDs.removeAll { $0 == v.id } }
                else if !settings.hiddenVolumeIDs.contains(v.id) { settings.hiddenVolumeIDs.append(v.id) }
            }
        )
    }
}
