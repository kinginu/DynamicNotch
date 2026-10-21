// Settings of the Color Picker widget (Settings ▸ Nook ▸ Widgets ▸ Color Picker).
import SwiftUI

struct ColorPickerWidgetSettingsView: View {
    @StoredSetting(.colorPickerWidgetSettings) private var settings
    @State private var store = ColorPickerHistoryStore.shared
    @State private var confirmingClear = false

    /// Example colour for the format list (the current colour when there is one).
    private var sample: PickedColor {
        store.current ?? PickedColor(red: 0.0, green: 0.478, blue: 1.0)
    }

    var body: some View {
        SettingsForm {
            Section {
                Picker("Copy format", selection: $settings.format) {
                    ForEach(ColorCopyFormat.allCases) { format in
                        Text(LocalizedStringKey(format.title)).tag(format)
                    }
                }
                LabeledContent("Example") {
                    Text(sample.formatted(settings.format, uppercaseHex: settings.uppercaseHex))
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
                Toggle("Uppercase HEX", isOn: $settings.uppercaseHex)
                Toggle("Copy automatically after picking", isOn: $settings.copyOnPick)
            } footer: {
                Text("Values are sRGB. Right-click a color in the widget to copy it in another format.")
                    .settingsFootnote()
            }

            Section {
                SettingsChoicePicker("Recent colors", selection: $settings.historyLimit,
                                     choices: ColorPickerWidgetSettings.historyLimitChoices) { n in
                    Text("\(n) colors")
                }
                SettingsHistoryRow(
                    summary: store.colors.count == 1
                        ? String(localized: "1 color in history")
                        : String(localized: "\(store.colors.count) colors in history"),
                    clearTitle: "Clear History…",
                    isEmpty: store.colors.isEmpty,
                    clear: { confirmingClear = true })
            } footer: {
                Text("Recent colors are kept only on this Mac (Application Support).")
                    .settingsFootnote()
            }
        }
        .onAppear { store.start() }
        .onChange(of: settings.historyLimit) { _, _ in store.trim() }
        .colorPickerDebugHook()
        .confirmationDialog("Clear recent colors?", isPresented: $confirmingClear) {
            Button("Clear History", role: .destructive) { store.clear() }
        } message: {
            Text("This removes all saved colors. It cannot be undone.")
        }
    }
}
