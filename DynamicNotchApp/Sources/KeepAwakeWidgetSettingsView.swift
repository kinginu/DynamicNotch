// Settings of the Keep Awake widget (Settings ▸ Nook ▸ Widgets ▸ Keep Awake).
import SwiftUI

struct KeepAwakeWidgetSettingsView: View {
    @StoredSetting(.keepAwakeWidgetSettings) private var settings
    @State private var manager = KeepAwakeManager.shared

    var body: some View {
        SettingsForm {
            Section {
                HStack {
                    Image(systemName: manager.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                        .foregroundStyle(manager.isActive ? AnyShapeStyle(KeepAwakeStyle.tint) : AnyShapeStyle(.secondary))
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(status(now: context.date))
                            .monospacedDigit()
                    }
                    Spacer()
                    Button(manager.isActive ? String(localized: "Turn Off") : String(localized: "Turn On")) {
                        manager.toggle()
                    }
                }
                if let error = manager.lastError {
                    Text(verbatim: error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Picker("Duration", selection: $settings.lastDuration) {
                    ForEach(KeepAwakeDuration.allCases, id: \.self) { d in
                        Text(d.title).tag(d)
                    }
                }
                Toggle("Allow display to sleep", isOn: $settings.allowDisplaySleep)
            } footer: {
                Text("The duration is used by the widget's switch; the chips in the widget start a session of their own length. With the display allowed to sleep, only idle system sleep is prevented. Closing the lid still sleeps the Mac.")
                    .settingsFootnote()
            }

            Section {
                Toggle("Show in the closed notch", isOn: $settings.showInClosedNotch)
                Toggle("Resume after relaunch", isOn: $settings.resumeAfterRelaunch)
            } footer: {
                Text("When resumed, a timed session keeps its original end time.")
                    .settingsFootnote()
            }
        }
        .onAppear { manager.start() }
    }

    private func status(now: Date) -> String {
        guard let session = manager.session else { return String(localized: "Off") }
        if let end = session.endDate {
            return String(localized: "On · \(KeepAwakeFormat.countdown(max(0, end.timeIntervalSince(now)))) left")
        }
        return String(localized: "On · until turned off")
    }
}
