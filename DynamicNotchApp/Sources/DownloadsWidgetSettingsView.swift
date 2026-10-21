// F8: Settings ▸ Nook ▸ Widgets ▸ Downloads (2026-10-20): watched folder, number of items,
// hidden files, the closed-notch progress indicator, and cleanup (age of "old" items, opt-in
// automatic move to the Trash — confirmed when turned on).
import SwiftUI
import AppKit

struct DownloadsWidgetSettingsView: View {
    @StoredSetting(.downloadsWidgetSettings) private var settings
    @State private var watcher = DownloadsWatcher.shared
    @State private var confirmingAutoClear = false
    /// Report appear / disappear to the watcher (false for offscreen DEBUG renders).
    var tracksVisibility = true

    var body: some View {
        SettingsForm {
            Section {
                LabeledContent("Folder") {
                    HStack(spacing: 6) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: settings.folderURL.path))
                            .resizable()
                            .frame(width: 16, height: 16)
                        Text(verbatim: FileManager.default.displayName(atPath: settings.folderURL.path))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(Text(verbatim: settings.folderURL.path))
                        Button("Choose…", action: chooseFolder)
                        if !settings.usesDefaultFolder {
                            Button("Use Downloads") { settings.folderPath = nil }
                        }
                    }
                }
                folderStatus
                SettingsChoicePicker("Show", selection: $settings.itemCount,
                                     choices: DownloadsWidgetSettings.itemCountChoices) { n in
                    Text(String(format: String(localized: "%lld items"), n))
                }
                Toggle("Show hidden files", isOn: $settings.showHidden)
                Toggle("Show download progress in the closed notch", isOn: $settings.showInClosedNotch)
            } footer: {
                Text("Downloads in progress from Safari, Chrome and Firefox are listed first with their progress.")
                    .settingsFootnote()
            }

            Section {
                SettingsChoicePicker("Old items", selection: $settings.clearAfterDays,
                                     choices: DownloadsWidgetSettings.clearAfterChoices) { d in
                    Text(String(format: String(localized: "Added more than %lld days ago"), d))
                }
                Toggle("Move old items to the Trash automatically", isOn: Binding(
                    get: { settings.autoClear },
                    set: { on in
                        if on { confirmingAutoClear = true } else { settings.autoClear = false }
                    }
                ))
            } header: {
                Text("Clean Up")
            } footer: {
                Text("Clear Old Items… in the widget's menu asks before moving anything. Hidden files and downloads in progress are never moved. Items in the Trash can be put back.")
                    .settingsFootnote()
            }
        }
        .confirmationDialog(
            String(format: String(localized: "Move items older than %lld days to the Trash automatically?"), settings.clearAfterDays),
            isPresented: $confirmingAutoClear
        ) {
            Button("Turn On", role: .destructive) { settings.autoClear = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(String(format: String(localized: "Items in “%@” added more than %lld days ago are moved to the Trash now and every few hours while the widget is in the Nook."),
                        FileManager.default.displayName(atPath: settings.folderURL.path), settings.clearAfterDays))
        }
        .onAppear { if tracksVisibility { watcher.setVisible(true) } }
        .onDisappear { if tracksVisibility { watcher.setVisible(false) } }
    }

    @ViewBuilder
    private var folderStatus: some View {
        switch watcher.status {
        case .denied:
            HStack {
                Label("DynamicNotch can't read this folder.", systemImage: "lock")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Open System Settings") { DownloadsWatcher.openFilesAndFoldersPrivacy() }
            }
        case .missing, .notFolder:
            Label("Folder not found", systemImage: "questionmark.folder")
                .foregroundStyle(.secondary)
        case .ok:
            Text(String(format: String(localized: "%lld items in the folder"), watcher.totalCount))
                .foregroundStyle(.secondary)
        case .unknown:
            EmptyView()
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = settings.folderURL
        panel.prompt = String(localized: "Choose")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.folderPath = url.standardizedFileURL == URL.downloadsDirectory.standardizedFileURL ? nil : url.path
    }
}
