// Settings ▸ Nook ▸ Widgets ▸ Quick Apps: the pinned
// apps (`quickAppsPaths`) — add (open panel, or drag .app files onto the pane), reorder (drag),
// remove — and the app-name toggle.
import SwiftUI
import UniformTypeIdentifiers

struct QuickAppsWidgetSettingsView: View {
    @StoredSetting(.quickAppsPaths) private var paths
    @StoredSetting(.quickAppsWidgetSettings) private var settings
    @State private var dropTargeted = false

    var body: some View {
        SettingsForm {
            Section {
                if paths.isEmpty {
                    Text("Drag apps here or click Add Apps…")
                        .foregroundStyle(.secondary)
                }
                ForEach(paths, id: \.self) { path in
                    HStack {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                            .resizable()
                            .frame(width: 20, height: 20)
                        Text(SettingsApps.name(atPath: path))
                        Spacer()
                        SettingsRemoveButton { paths.removeAll { $0 == path } }
                    }
                }
                .onMove { from, to in paths.move(fromOffsets: from, toOffset: to) }
            } header: {
                SettingsSectionHeader("Apps (drag to reorder)") {
                    Button("Add Apps…") { QuickAppsPicker.addApps() }
                }
            }
            Section {
                Toggle("Show app names", isOn: $settings.showAppNames)
            }
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 2).padding(4)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { QuickAppsPicker.add([url]) }
                }
            }
            return true
        }
    }
}
