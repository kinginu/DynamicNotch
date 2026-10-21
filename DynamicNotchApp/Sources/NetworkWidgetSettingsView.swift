// Settings of the Network widget (Settings ▸ Nook ▸ Widgets ▸ Network).
import SwiftUI

struct NetworkWidgetSettingsView: View {
    @StoredSetting(.networkWidgetSettings) private var settings
    @State private var monitor = NetworkMonitor.shared

    var body: some View {
        SettingsForm {
            Section {
                Picker("Interface", selection: $settings.interfaceName) {
                    Text(automaticTitle).tag(String?.none)
                    ForEach(interfaceChoices, id: \.self) { name in
                        Text(verbatim: interfaceTitle(name)).tag(String?.some(name))
                    }
                }
                SettingsChoicePicker("Sampling interval", selection: $settings.samplingInterval,
                                     choices: NetworkWidgetSettings.samplingIntervalChoices) { seconds in
                    Text(seconds == 1 ? String(localized: "Every second") : String(localized: "Every \(seconds) seconds"))
                }
                SettingsChoicePicker("History", selection: $settings.historySeconds,
                                     choices: NetworkWidgetSettings.historySecondsChoices) { seconds in
                    Text(seconds == 60 ? String(localized: "1 minute") : String(localized: "\(seconds / 60) minutes"))
                }
            } footer: {
                Text("Automatic follows the interface macOS sends traffic through. Throughput is measured while the widget is in the Nook, so the graph already has history when the Nook opens.")
                    .settingsFootnote()
            }

            Section {
                Toggle("Show public IP address", isOn: $settings.showsPublicIP)
                if settings.showsPublicIP {
                    LabeledContent("Public IP address") {
                        HStack {
                            Text(verbatim: monitor.publicIP ?? (monitor.publicIPFailed ? "—" : "…"))
                                .font(.body.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            Button("Refresh") { monitor.refreshPublicIP() }
                                .controlSize(.small)
                        }
                    }
                }
            } footer: {
                Text("When on, the widget asks api.ipify.org for the address your traffic appears to come from: when the network changes and every 10 minutes while the Nook is open. Off by default.")
                    .settingsFootnote()
            }

            if monitor.wifi?.isAssociated == true, monitor.wifi?.ssid == nil,
               !PermissionCenter.shared.isGranted(.location) {
                Section {
                    PermissionStatusRow(
                        kind: .location,
                        message: "macOS shows Wi‑Fi network names only to apps with Location Services access. Without it, the widget shows “Wi‑Fi” with the signal, channel and rate.")
                }
            }
        }
        .onAppear { monitor.setVisible(true) }
        .onDisappear { monitor.setVisible(false) }
        .networkWidgetDebugHook()
    }

    private var automaticTitle: String {
        if let primary = monitor.defaultInterfaceName ?? monitor.primaryInterfaceName {
            return String(localized: "Automatic (\(interfaceTitle(primary)))")
        }
        return String(localized: "Automatic")
    }

    private var interfaceChoices: [String] {
        var names = monitor.interfaces.map(\.bsdName)
        if let chosen = settings.interfaceName, !names.contains(chosen) { names.append(chosen) }
        return names
    }

    private func interfaceTitle(_ name: String) -> String {
        guard let iface = monitor.interfaces.first(where: { $0.bsdName == name }) else {
            return String(localized: "\(name) (not connected)")
        }
        return "\(iface.displayName) (\(name))"
    }
}
