// Settings ▸ Nook ▸ Widgets ▸ Batteries (2026-10-20): this Mac on/off, hide accessories
// below a level, refresh interval, Bluetooth access (for Bluetooth LE accessories), and the list
// of devices currently found.
import SwiftUI

struct BatteriesWidgetSettingsView: View {
    @StoredSetting(.batteriesWidgetSettings) private var settings
    @State private var manager = BatteryDevicesManager.shared

    var body: some View {
        SettingsForm {
            Section {
                Toggle("Show this Mac", isOn: $settings.showThisMac)
                Picker("Hide devices below", selection: $settings.hideBelowPercent) {
                    Text("None").tag(Int?.none)
                    ForEach(BatteriesWidgetSettings.hideBelowChoices, id: \.self) { p in
                        Text(verbatim: "\(p)%").tag(Int?.some(p))
                    }
                }
                SettingsChoicePicker("Refresh every", selection: $settings.refreshInterval,
                                     choices: BatteriesWidgetSettings.refreshIntervalChoices) { s in
                    Text(Duration.seconds(s), format: .units(allowed: [.minutes, .seconds], width: .wide))
                }
            } footer: {
                Text("Levels also update when a power adapter or a Bluetooth device connects or disconnects.")
                    .settingsFootnote()
            }

            ChargeLimitSettingsSection()  // F1: "Limit charging to 80 %" (ChargeLimitViews.swift)

            Section {
                PermissionStatusRow(
                    kind: .bluetooth,
                    granted: "Bluetooth access is on.",
                    notDetermined: "Allow Bluetooth access to show the battery of Bluetooth LE keyboards and mice.",
                    denied: "Bluetooth access is off. Turn on DynamicNotch in System Settings ▸ Privacy & Security ▸ Bluetooth to show Bluetooth LE keyboards and mice.",
                    allowTitle: "Allow Bluetooth Access",
                    allow: { manager.requestBluetoothAccess() })
            } header: {
                Text("Bluetooth")
            } footer: {
                Text("This Mac, Magic accessories and AirPods are shown without Bluetooth access.")
                    .settingsFootnote()
            }

            Section("Devices") {
                if manager.devices.isEmpty {
                    Text("No batteries").foregroundStyle(.secondary)
                }
                ForEach(manager.devices) { device in
                    SettingsSymbolRow(systemImage: device.kind.systemImage) {
                        Text(device.name)
                    } trailing: {
                        Text(verbatim: "\(device.percent)%")
                            .monospacedDigit()
                            .foregroundStyle(device.isLowPower ? .red : .secondary)
                    }
                }
            }
        }
        .onAppear { manager.setVisible(true) }
        .onDisappear { manager.setVisible(false) }
        .onChange(of: settings.refreshInterval) { _, _ in manager.reschedule() }
    }
}
