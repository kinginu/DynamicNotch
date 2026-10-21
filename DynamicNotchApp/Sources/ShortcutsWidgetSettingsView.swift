// Settings ▸ Nook ▸ Widgets ▸ Shortcuts: the user's shortcuts (`shortcuts list`)
// with a checkbox each; the checked ones appear in the widget, in the order they were checked
// (`shortcutsWidgetSelection`).
import SwiftUI

struct ShortcutsWidgetSettingsView: View {
    @StoredSetting(.shortcutsWidgetSelection) private var selection
    @State private var manager = ShortcutsManager.shared

    var body: some View {
        SettingsForm {
            Section {
                if manager.shortcuts.isEmpty {
                    HStack {
                        Text(manager.isLoading ? "Loading shortcuts…" : "No Shortcuts")
                            .foregroundStyle(.secondary)
                        Spacer()
                        if manager.isLoading { ProgressView().controlSize(.small) }
                    }
                } else {
                    ForEach(manager.shortcuts, id: \.self) { name in
                        Toggle(isOn: binding(for: name)) {
                            Label(name, systemImage: "sparkles")
                        }
                    }
                }
                // shortcuts chosen earlier that no longer exist
                ForEach(selection.filter { !manager.shortcuts.contains($0) && !manager.isLoading && !manager.shortcuts.isEmpty }, id: \.self) { name in
                    Toggle(isOn: binding(for: name)) {
                        Label(name + " " + String(localized: "(not found)"), systemImage: "exclamationmark.triangle")
                    }
                }
            } header: {
                SettingsSectionHeader("Shortcuts shown in the widget") {
                    Button("Reload") { Task { await manager.refresh() } }
                        .disabled(manager.isLoading)
                    Button("Open Shortcuts") {
                        if let url = SettingsApps.url(of: "com.apple.shortcuts") {
                            NSWorkspace.shared.openApplication(at: url, configuration: .init())
                        }
                    }
                }
            }
        }
        .task { await manager.refresh() }
    }

    private func binding(for name: String) -> Binding<Bool> {
        Binding(
            get: { selection.contains(name) },
            set: { on in
                if on {
                    if !selection.contains(name) { selection.append(name) }
                } else {
                    selection.removeAll { $0 == name }
                }
            }
        )
    }
}
