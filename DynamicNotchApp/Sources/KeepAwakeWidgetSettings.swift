// Settings of the Keep Awake widget (2026-10-20). Key "keepAwakeWidgetSettings"
// (typed key still in Support/Ext-C.swift; pattern: SettingsUI/SettingsDecoding.swift). The running session itself (end time) is
// not a setting: KeepAwakeManager persists it separately under "keepAwakeSession".
import Foundation

/// Duration chips of the Keep Awake widget.
enum KeepAwakeDuration: String, Codable, CaseIterable, Hashable {
    case fifteenMinutes, oneHour, twoHours, indefinite

    /// Seconds, or nil for "until turned off".
    var seconds: TimeInterval? {
        switch self {
        case .fifteenMinutes: return 15 * 60
        case .oneHour:        return 60 * 60
        case .twoHours:       return 2 * 60 * 60
        case .indefinite:     return nil
        }
    }

    /// Short chip label ("15m", "1h", "2h", "∞").
    var chipLabel: String {
        switch self {
        case .fifteenMinutes: return "15m"
        case .oneHour:        return "1h"
        case .twoHours:       return "2h"
        case .indefinite:     return "∞"
        }
    }

    /// Full name (settings picker, accessibility).
    var title: String {
        switch self {
        case .fifteenMinutes: return String(localized: "15 minutes")
        case .oneHour:        return String(localized: "1 hour")
        case .twoHours:       return String(localized: "2 hours")
        case .indefinite:     return String(localized: "Until turned off")
        }
    }
}

struct KeepAwakeWidgetSettings: Preferences, WidgetPrefs, Codable, Equatable, Hashable {
    /// Hold only a system-sleep assertion (PreventUserIdleSystemSleep): the display may sleep, the
    /// Mac stays awake. Off = PreventUserIdleDisplaySleep (display and Mac stay awake).
    var allowDisplaySleep: Bool = false
    /// Show the cup + remaining time in the closed notch while active.
    var showInClosedNotch: Bool = true
    /// Resume a running session (same end time) when the app is relaunched.
    var resumeAfterRelaunch: Bool = true
    /// Duration used by the widget's on/off switch (the last chip chosen).
    var lastDuration: KeepAwakeDuration = .oneHour

    static let `default` = KeepAwakeWidgetSettings()

    var gridSizeType: NookWidget.NookGridSizeType { .small }

    init() {}

    // Tolerant decoding: a missing or undecodable field keeps its default.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.decodeSetting(.allowDisplaySleep, into: &allowDisplaySleep)
        c.decodeSetting(.showInClosedNotch, into: &showInClosedNotch)
        c.decodeSetting(.resumeAfterRelaunch, into: &resumeAfterRelaunch)
        c.decodeSetting(.lastDuration, into: &lastDuration)
    }

    private enum CodingKeys: String, CodingKey {
        case allowDisplaySleep, showInClosedNotch, resumeAfterRelaunch, lastDuration
    }
}
