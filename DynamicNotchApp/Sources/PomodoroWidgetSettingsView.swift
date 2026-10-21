// Settings ▸ Widgets ▸ Focus (Pomodoro widget, 2026-10-20).
import SwiftUI

struct PomodoroWidgetSettingsView: View {
    @StoredSetting(.pomodoroWidgetSettings) private var settings

    var body: some View {
        SettingsForm {
            Section {
                minutesPicker("Focus", selection: $settings.focusMinutes, choices: PomodoroWidgetSettings.focusChoices)
                minutesPicker("Short Break", selection: $settings.shortBreakMinutes, choices: PomodoroWidgetSettings.shortBreakChoices)
                minutesPicker("Long Break", selection: $settings.longBreakMinutes, choices: PomodoroWidgetSettings.longBreakChoices)
                SettingsChoicePicker("Long break after", selection: $settings.longBreakEvery,
                                     choices: PomodoroWidgetSettings.longBreakEveryChoices) { n in
                    Text("\(n) sessions")
                }
            } footer: {
                Text("New lengths apply from the next session that starts.")
                    .settingsFootnote()
            }
            Section {
                Toggle("Start breaks automatically", isOn: $settings.autoStartBreaks)
                Toggle("Start focus sessions automatically", isOn: $settings.autoStartFocus)
                Toggle("Show the session in the closed notch", isOn: $settings.showInClosedNotch)
            } footer: {
                Text("When a session or break ends, the Timer widget's sound plays and repeats until you stop it or the timer's alert duration passes (Settings ▸ Widgets ▸ Timer).")
                    .settingsFootnote()
            }
        }
    }

    private func minutesPicker(_ title: LocalizedStringKey, selection: Binding<Int>, choices: [Int]) -> some View {
        SettingsChoicePicker(title, selection: selection, choices: choices) { minutes in
            Text("\(minutes) min")
        }
    }
}
