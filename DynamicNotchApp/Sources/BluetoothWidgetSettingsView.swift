// Settings ▸ Nook ▸ Widgets ▸ Bluetooth (2026-10-20): show only favourites, hide unnamed
// devices, Bluetooth state / access, and the paired devices with a favourite star each.
import SwiftUI

struct BluetoothWidgetSettingsView: View {
    @StoredSetting(.bluetoothWidgetSettings) private var settings
    @State private var model = BluetoothWidgetModel.shared

    var body: some View {
        SettingsForm {
            Section {
                Toggle("Show only favourites", isOn: $settings.showOnlyFavourites)
                Toggle("Hide unnamed devices", isOn: $settings.hideUnnamed)
            } footer: {
                Text("Click a device in the widget to connect or disconnect it; right-click it to add it to the favourites.")
                    .settingsFootnote()
            }

            Section {
                LabeledContent("Status") {
                    switch model.power {
                    case .on: Text("On")
                    case .off: Text("Off")
                    case .unavailable: Text("Unavailable")
                    case .unknown: Text(verbatim: "—")
                    }
                }
                PermissionStatusRow(
                    kind: .bluetooth,
                    granted: "Bluetooth access is on.",
                    notDetermined: "Allow access to show your paired devices.",
                    denied: "Turn on DynamicNotch in Privacy & Security ▸ Bluetooth.",
                    allowTitle: "Allow Bluetooth Access",
                    allow: { model.requestAccess() })
            } header: {
                Text("Bluetooth")
            } footer: {
                Text("Bluetooth is turned on and off in Control Center or System Settings.")
                    .settingsFootnote()
            }

            Section("Devices") {
                if model.devices.isEmpty {
                    Text("No devices").foregroundStyle(.secondary)
                }
                ForEach(model.devices) { device in
                    SettingsSymbolRow(systemImage: device.kind.systemImage) {
                        Text(verbatim: device.displayName)
                            .foregroundStyle(device.isUnnamed ? .secondary : .primary)
                    } trailing: {
                        Text(device.isConnected ? "Connected" : "Not Connected")
                            .foregroundStyle(.secondary)
                        favouriteButton(device.id)
                    }
                }
            }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private func favouriteButton(_ id: String) -> some View {
        let isFavourite = settings.isFavourite(id)
        return Button {
            settings.toggleFavourite(id)
        } label: {
            Image(systemName: isFavourite ? "star.fill" : "star")
                .foregroundStyle(isFavourite ? AnyShapeStyle(Color.yellow) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.plain)
        .help(Text(isFavourite ? "Remove from Favourites" : "Add to Favourites"))
    }
}
