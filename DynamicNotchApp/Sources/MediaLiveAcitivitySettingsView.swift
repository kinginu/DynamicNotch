// Settings of the media live activity (Live Activities ▸ Customize): the animation
// effect, the artwork tint, and the custom GIF with its scale (MediaLiveActivitySettings), as a
// grouped form.
import SwiftUI
import UniformTypeIdentifiers

struct MediaLiveAcitivitySettingsView: View {
    @StoredSetting(.mediaLiveActivitySettings) private var settings

    var body: some View {
        SettingsForm {
            Section("Animation Effect") {
                Picker("Effect", selection: $settings.effect) {
                    ForEach(MediaLiveActivityEffectEnum.allCases) { effect in
                        Text(effect.description)
                            .tag(effect)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .padding(.vertical, 4)

                Toggle("Tint with the artwork colour", isOn: $settings.isAutomaticallyColored)

                if settings.effect == .customGIF {
                    HStack {
                        SliderPlusNegative(value: $settings.gifScale, lowerBound: -1.0, upperBound: 1.0)
                            .frame(minWidth: 80, idealWidth: 100, maxWidth: .infinity, alignment: .leading)
                        Text("Scale")
                    }
                    .padding(.vertical, 4)

                    LabeledContent {
                        Text(settings.customGifURL?.lastPathComponent ?? String(localized: "None selected"))
                            .foregroundStyle(.secondary)
                    } label: {
                        Button("Select GIF File") { selectGIFFile() }
                    }
                }
            }
        }
    }

    /// GIF open panel, as a sheet on the settings window.
    private func selectGIFFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.gif]
        guard let keyWindow = NSApp.keyWindow else { return }
        panel.beginSheetModal(for: keyWindow) { response in
            if response == .OK, let url = panel.url {
                settings.customGifURL = url
            }
        }
    }
}
