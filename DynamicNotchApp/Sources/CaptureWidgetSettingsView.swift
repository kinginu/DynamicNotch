// Settings of the Capture widget (Settings ▸ Nook ▸ Widgets ▸ Capture).
import SwiftUI

struct CaptureWidgetSettingsView: View {
    @StoredSetting(.captureWidgetSettings) private var settings

    var body: some View {
        SettingsForm {
            Section {
                Picker("Save to", selection: $settings.destination) {
                    ForEach(CaptureDestination.allCases) { d in
                        Text(d.title).tag(d)
                    }
                }
                TextField("File name", text: $settings.filenamePattern, prompt: Text(CaptureWidgetSettings.defaultPattern))
                LabeledContent("Example") {
                    Text(settings.fileName(kind: .area) + "." + settings.imageFormat.rawValue)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Picker("Image format", selection: $settings.imageFormat) {
                    ForEach(CaptureImageFormat.allCases) { f in
                        Text(f.title).tag(f)
                    }
                }
            } header: {
                Text("Output")
            } footer: {
                Text("Tokens: {kind} (Screenshot or Screen Recording), {date}, {time}. Recordings cannot go to the clipboard: they are saved on the Desktop and the file is copied. Tray adds the capture to the Files Tray.")
                    .settingsFootnote()
            }

            Section {
                SettingsChoicePicker("Delay", selection: $settings.delaySeconds,
                                     choices: CaptureWidgetSettings.delayChoices) { s in
                    Text(s == 0 ? String(localized: "No delay") : String(localized: "\(s) s"))
                }
                Toggle("Play sounds", isOn: $settings.playSounds)
                Toggle("Include window shadow", isOn: $settings.windowShadow)
                Toggle("Reopen the notch after a screenshot", isOn: $settings.reopenNotch)
            } header: {
                Text("Screenshots")
            } footer: {
                Text("The notch closes before every capture so it is not in the picture. Area and Window wait for your selection; press Esc to cancel. Screen captures the main display.")
                    .settingsFootnote()
            }

            Section {
                SettingsChoicePicker("Stop after", selection: $settings.recordingLimitSeconds,
                                     choices: CaptureWidgetSettings.recordingLimitChoices) { s in
                    Text(s == 0 ? String(localized: "Until stopped") : CaptureElapsed.format(TimeInterval(s)))
                }
                Toggle("Show clicks", isOn: $settings.showClicks)
            } header: {
                Text("Screen recording")
            } footer: {
                Text("Records the main display without audio. Stop it with the Stop button in the widget; while the notch is closed a red dot and the elapsed time appear beside it.")
                    .settingsFootnote()
            }

            AutomationCaptureSettingsSection()

            Section {
                PermissionStatusRow(
                    kind: .screenRecording,
                    message: "Screen Recording access is off. Without it, captures show only the desktop and recordings fail.",
                    granted: "Screen Recording access is on.")
            } header: {
                Text("Permission")
            } footer: {
                Text("macOS asks the first time. After switching it on in System Settings ▸ Privacy & Security ▸ Screen & System Audio Recording, quit and reopen the app.")
                    .settingsFootnote()
            }
        }
    }
}
