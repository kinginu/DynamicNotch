// Settings of the Menu Bar widget (Settings ▸ Nook ▸ Widgets ▸ Menu Bar).
import SwiftUI

struct MenuBarItemsWidgetSettingsView: View {
    @StoredSetting(.menuBarItemsWidgetSettings) private var settings
    @StoredSetting(.nookSettings) private var nookSettings
    @State private var manager = MenuBarItemsManager.shared

    private var inNook: Bool { nookSettings.widgets.contains(.menuBarItems) }

    var body: some View {
        SettingsForm {
            Section {
                Toggle("Hide menu bar items", isOn: Binding(
                    get: { settings.hidingEnabled },
                    set: { settings.hidingEnabled = $0; manager.applySettings() }
                ))
                Toggle("Show hidden items in the menu bar", isOn: Binding(
                    get: { settings.showHiddenItems },
                    set: { manager.setShowHiddenItems($0) }
                ))
                .disabled(!settings.hidingEnabled || !inNook)
                Toggle("Show item images", isOn: $settings.showItemImages)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DynamicNotch adds a separator (‹) to the menu bar. Items to its left are hidden from the menu bar and appear in the Menu Bar widget, where clicking one opens it. To choose which items are hidden, show the separator, then hold ⌘ and drag menu bar items across it.")
                    Text("Quit DynamicNotch or turn hiding off to bring every item back.")
                    if !inNook {
                        Text("Add the Menu Bar widget to the Nook to use hiding.")
                            .foregroundStyle(.orange)
                    }
                }
                .settingsFootnote()
            }

            Section {
                PermissionStatusRow(
                    kind: .screenRecording, showsTitle: true,
                    message: "Shows the hidden items as images. Without it, the widget lists their names.",
                    allow: { manager.requestScreenRecording() })
                PermissionStatusRow(
                    kind: .accessibility, showsTitle: true,
                    message: "Clicks an item for you and moves items. Without it, clicking an item shows the hidden items in the menu bar for a few seconds.",
                    allow: { manager.requestAccessibility() })
            } header: {
                Text("Permissions")
            } footer: {
                Text("After allowing access in System Settings, you may need to quit and reopen DynamicNotch.")
                    .settingsFootnote()
            }

            Section {
                if manager.hiddenItems.isEmpty {
                    Text(manager.separatorActive ? "No hidden items" : "Hiding is off")
                        .foregroundStyle(.secondary)
                }
                ForEach(manager.hiddenItems) { item in
                    HStack(spacing: 8) {
                        SettingsAppIcon(bundleID: item.bundleID, fallbackSymbol: "menubar.dock.rectangle")
                        Text(item.appName)
                        Spacer()
                        if let id = item.bundleID, settings.alwaysShownBundleIDs.contains(id) {
                            Button("Move to Menu Bar") { manager.moveToShown(item) }
                                .help(String(localized: "⌘-drags this item to the right of the separator (needs Accessibility)."))
                        } else if let id = item.bundleID {
                            Button("Always Show") { addAlwaysShown(id) }
                        }
                    }
                }
            } header: {
                Text("Hidden now")
            }

            Section {
                if settings.alwaysShownBundleIDs.isEmpty {
                    Text("No apps")
                        .foregroundStyle(.secondary)
                }
                ForEach(settings.alwaysShownBundleIDs, id: \.self) { bundleID in
                    HStack(spacing: 8) {
                        SettingsAppIcon(bundleID: bundleID, fallbackSymbol: "menubar.dock.rectangle")
                        Text(SettingsApps.name(of: bundleID))
                        if manager.hiddenItems.contains(where: { $0.bundleID == bundleID }) {
                            Text("Hidden")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        Spacer()
                        SettingsRemoveButton { settings.alwaysShownBundleIDs.removeAll { $0 == bundleID } }
                    }
                }
                Button("Add App…") { SettingsApps.chooseBundleIDs().forEach(addAlwaysShown) }
            } header: {
                Text("Always show in menu bar")
            } footer: {
                Text("Items of these apps are marked with a pin when they end up hidden. Move to Menu Bar puts them back to the right of the separator.")
                    .settingsFootnote()
            }
        }
        .onAppear { manager.widgetAppeared() }
        .onDisappear { manager.widgetDisappeared() }
    }

    private func addAlwaysShown(_ bundleID: String) {
        guard !settings.alwaysShownBundleIDs.contains(bundleID) else { return }
        settings.alwaysShownBundleIDs.append(bundleID)
    }
}
