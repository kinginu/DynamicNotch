// Settings ▸ Tray: the options the tray implements (TraySettings).
import SwiftUI

struct TraySettingsView: View {
    @StoredSetting(.traySettings) private var settings
    private var tray: Tray { Tray.shared }

    var body: some View {
        SettingsForm {
            Section {
                Toggle(isOn: $settings.copyFiles) {
                    Text("Copy dropped files into the tray")
                    Text("When off, the tray keeps a reference to the original file instead of a copy.")
                }
                Toggle("Keep files after quitting", isOn: $settings.keepFilesAfterQuit)
                Toggle("Remove files after dragging them out", isOn: $settings.removeAfterDraggingOut)
                Toggle("Show file names", isOn: $settings.showLabels)
            } header: {
                Text("Files Tray")
            }

            Section {
                LabeledContent("Files in tray:") {
                    Text("\(tray.files.count)")
                        .monospacedDigit()
                }
                HStack {
                    Button("Show in Finder") {
                        if let dir = tray.storageDirectory {
                            NSWorkspace.shared.activateFileViewerSelecting([dir])
                        }
                    }
                    Button("Clear Tray", role: .destructive) {
                        tray.removeAll()
                    }
                    .disabled(tray.files.isEmpty)
                }
            }
        }
        .onChange(of: settings.showLiveActivity) { _, _ in tray.updateLiveActivity() }
        .onChange(of: settings.keepFilesAfterQuit) { _, _ in tray.filesDidChange() }
    }
}
