// Settings ▸ Nook ▸ Widgets ▸ Audio (2026-10-20): inputs on/off, volume on/off, input level
// on/off with the microphone access state, and the devices currently found.
import SwiftUI
import CoreAudio

struct AudioDevicesWidgetSettingsView: View {
    @StoredSetting(.audioDevicesWidgetSettings) private var settings
    @State private var manager = AudioDevicesManager.shared

    var body: some View {
        SettingsForm {
            Section {
                Toggle("Show input devices", isOn: $settings.showInputs)
                Toggle("Show output volume", isOn: $settings.showVolume)
                Toggle("Show input level", isOn: $settings.showInputLevel)
                    .disabled(!settings.showInputs)
            } footer: {
                Text("Click a device in the widget to make it the default output or input, as in Control Center.")
                    .settingsFootnote()
            }

            AirPodsListeningModeSettingsSection() // F7:

            Section {
                PermissionStatusRow(
                    kind: .microphone,
                    granted: "Microphone access is on.",
                    notDetermined: "Allow microphone access to show the input level.",
                    denied: "Microphone access is off. Turn on DynamicNotch in System Settings ▸ Privacy & Security ▸ Microphone to show the input level.",
                    unavailable: "This build is not set up for microphone access, so the input level is not shown.",
                    allowTitle: "Allow Microphone Access")
            } header: {
                Text("Input Level")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("The level is measured only while the Nook is open. macOS shows the microphone indicator while it runs.")
                    if manager.defaultInputIsBluetooth {
                        Text("The level is not shown for a Bluetooth input: opening its microphone would switch the headset to lower-quality call audio.")
                    }
                }
                .settingsFootnote()
            }

            Section("Output Devices") {
                deviceList(manager.outputs, selected: manager.defaultOutputID, input: false)
            }
            if settings.showInputs {
                Section("Input Devices") {
                    deviceList(manager.inputs, selected: manager.defaultInputID, input: true)
                }
            }
        }
        .onAppear { manager.start() }
    }

    @ViewBuilder
    private func deviceList(_ devices: [AudioDevice], selected: AudioObjectID, input: Bool) -> some View {
        if devices.isEmpty {
            Text(input ? "No input devices" : "No output devices").foregroundStyle(.secondary)
        }
        ForEach(devices) { device in
            SettingsSymbolRow(systemImage: device.systemImage(input: input)) {
                Text(device.name)
            } trailing: {
                if device.id == selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel(Text("Default"))
                }
            }
        }
    }
}
