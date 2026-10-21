// Settings ▸ Nook ▸ Widgets ▸ Displays (2026-10-20): turn each connected display on / off
// in the widget, DDC/CI for external monitors on / off, which DDC controls to show, how often to
// read them, and the backend each display uses.
import SwiftUI

struct DisplaysWidgetSettingsView: View {
    @StoredSetting(.displaysWidgetSettings) private var settings
    @State private var service = DisplayControlService.shared

    var body: some View {
        SettingsForm {
            Section {
                if service.displays.isEmpty {
                    Text("No displays").foregroundStyle(.secondary)
                }
                ForEach(service.displays) { display in
                    Toggle(isOn: Binding(
                        get: { settings.isEnabled(display) },
                        set: { settings.setEnabled($0, display) }
                    )) {
                        SettingsSymbolRow(systemImage: display.systemImage) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(display.name)
                                Text(statusText(display))
                                    .settingsFootnote()
                            }
                        }
                    }
                }
            } header: {
                Text("Displays")
            } footer: {
                Text("Turned-off displays are not shown in the widget and are not read.")
                    .settingsFootnote()
            }

            Section {
                Toggle("Control external monitors over DDC/CI", isOn: $settings.ddcEnabled)
                Toggle("Show contrast", isOn: $settings.showContrast)
                    .disabled(!settings.ddcEnabled)
                Toggle("Show volume", isOn: $settings.showVolume)
                    .disabled(!settings.ddcEnabled)
                Toggle("Show input source", isOn: $settings.showInputSource)
                    .disabled(!settings.ddcEnabled)
                Picker("Read monitors every", selection: $settings.refreshInterval) {
                    ForEach(DisplaysWidgetSettings.refreshIntervalChoices, id: \.self) { s in
                        Text(Duration.seconds(s), format: .units(allowed: [.minutes, .seconds], width: .wide)).tag(s)
                    }
                }
                .disabled(!settings.ddcEnabled)
            } header: {
                Text("External Monitors")
            } footer: {
                Text("DDC/CI works with most monitors connected over USB-C, Thunderbolt or DisplayPort. It may not work through some docks and adapters, or over the HDMI port of some Macs. Volume is shown only for monitors that report speakers. The input source is shown, not switched.")
                    .settingsFootnote()
            }
        }
        .onAppear { service.setVisible(true) }
        .onDisappear { service.setVisible(false) }
        .onChange(of: settings.refreshInterval) { _, _ in service.reschedule() }
        .onChange(of: settings) { _, _ in service.refresh() }
    }

    private func statusText(_ display: DisplayInfo) -> String {
        let s = service.state(display.id)
        if display.isBuiltIn {
            return s.brightness == nil
                ? String(localized: "Built-in · brightness unavailable")
                : String(format: String(localized: "Built-in · %@"), service.hardware.builtInBackendName)
        }
        switch s.ddc {
        case .available:
            let names = DisplayControl.allCases.filter { s.isAvailable($0) }.map(Self.controlName)
            return String(format: String(localized: "DDC/CI · %@"), names.joined(separator: ", "))
        case .probing:
            return String(localized: "DDC/CI · checking…")
        case .disabled, .notApplicable:
            return String(localized: "DDC/CI off")
        case .unavailable(let why):
            return String(localized: String.LocalizationValue(why))
        }
    }

    static func controlName(_ c: DisplayControl) -> String {
        switch c {
        case .brightness: return String(localized: "Brightness")
        case .contrast:   return String(localized: "Contrast")
        case .volume:     return String(localized: "Volume")
        case .input:      return String(localized: "Input")
        }
    }
}
