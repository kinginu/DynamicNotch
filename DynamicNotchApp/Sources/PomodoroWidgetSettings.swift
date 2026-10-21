// Settings of the Focus (Pomodoro) widget (2026-10-20). Key "pomodoroWidgetSettings"
// (declared at the end of this file; pattern: SettingsUI/SettingsDecoding.swift).
// The running session itself is not a setting: PomodoroStore persists it under
// its own UserDefaults key. The end-of-phase sound and the alert duration are the Timer widget's
// ("When Timer Ends", "Alert Duration" — TimerWidgetSettings).
import Foundation

struct PomodoroWidgetSettings: Preferences, WidgetPrefs, Codable, Equatable, Hashable {
    /// Length of a focus session (minutes).
    var focusMinutes: Int = 25
    /// Length of a short break (minutes).
    var shortBreakMinutes: Int = 5
    /// Length of a long break (minutes).
    var longBreakMinutes: Int = 15
    /// A long break follows every `longBreakEvery` completed focus sessions.
    var longBreakEvery: Int = 4
    /// Start the break automatically when a focus session ends.
    var autoStartBreaks: Bool = false
    /// Start the next focus session automatically when a break ends.
    var autoStartFocus: Bool = false
    /// Show a running / paused session in the closed notch.
    var showInClosedNotch: Bool = true

    static let focusChoices = [15, 20, 25, 30, 45, 50, 60, 90]
    static let shortBreakChoices = [3, 5, 10, 15]
    static let longBreakChoices = [10, 15, 20, 25, 30]
    static let longBreakEveryChoices = [2, 3, 4, 5, 6]

    static let `default` = PomodoroWidgetSettings()

    var gridSizeType: NookWidget.NookGridSizeType { NookWidget.pomodoro.gridSizeType }

    init() {}

    /// Seconds of `phase` (at least one minute).
    func seconds(of phase: PomodoroPhase) -> Int {
        let minutes: Int
        switch phase {
        case .focus: minutes = focusMinutes
        case .shortBreak: minutes = shortBreakMinutes
        case .longBreak: minutes = longBreakMinutes
        }
        return max(1, minutes) * 60
    }

    // Tolerant decoding: a missing or undecodable field keeps its default.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.decodeSetting(.focusMinutes, into: &focusMinutes)
        c.decodeSetting(.shortBreakMinutes, into: &shortBreakMinutes)
        c.decodeSetting(.longBreakMinutes, into: &longBreakMinutes)
        c.decodeSetting(.longBreakEvery, into: &longBreakEvery)
        c.decodeSetting(.autoStartBreaks, into: &autoStartBreaks)
        c.decodeSetting(.autoStartFocus, into: &autoStartFocus)
        c.decodeSetting(.showInClosedNotch, into: &showInClosedNotch)
    }

    private enum CodingKeys: String, CodingKey {
        case focusMinutes, shortBreakMinutes, longBreakMinutes, longBreakEvery
        case autoStartBreaks, autoStartFocus, showInClosedNotch
    }
}

extension SettingKey {
    static let pomodoroWidgetSettings = "pomodoroWidgetSettings"
}

extension StoredKeys {
    static let pomodoroWidgetSettings = Key<PomodoroWidgetSettings>(SettingKey.pomodoroWidgetSettings, default: .default)
}
