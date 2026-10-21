// Settings of the Timer widget (and the end-of-phase sound / alert duration the
// Focus widget shares). Key "timerWidgetSettings" (typed key still in Support/Ext-C.swift; pattern:
// SettingsUI/SettingsDecoding.swift). The running timers and the Recents are stored by
// NookTimersStore, not here.
import Foundation

struct TimerWidgetSettings: Preferences, WidgetPrefs, Codable, Equatable, Hashable {
    // NotchView reads `.disabled` / `.gridPoint` on every widget settings value.
    var disabled: Bool = false
    var gridPoint: NookGrid.Point = NookGrid.Point(value: 0)
    /// Stored grid size (kept for compatibility; the width comes from the Nook grid).
    var gridSize: NookGrid.Size = NookGrid.Size(width: .init(value: 1), height: .init(value: 1))
    /// Show seconds in the countdown.
    var showSeconds: Bool = true
    /// Milliseconds in the countdown (unused: the countdown has one-second resolution).
    var showMilliseconds: Bool = false
    /// "When Timer Ends" (iOS Clock): a system sound name (/System/Library/Sounds),
    /// `Self.stopPlayingSound` (pause the playing media instead, like iOS's "Stop Playing"), or ""
    /// (no sound).
    var soundName: String = "Glass"
    /// How long an ended timer keeps ringing / alerting in the closed notch before it is dismissed
    /// automatically (seconds; 0 = until stopped).
    var alertSeconds: Int = 60
    /// Show running timers in the closed notch (Dynamic Island compact / minimal).
    var showInClosedNotch: Bool = true
    /// Five fixed preset slots shown as the widget's chips (duration + optional label). Always
    /// `TimerPreset.slotCount` entries (normalized on decode); a slot set to 0 s is hidden.
    var presets: [TimerPreset] = TimerPreset.defaults
    /// List the Recents in the widget's "…" menu (the menu is hidden when off or empty).
    var showRecents: Bool = true

    static let stopPlayingSound = "stopPlaying"

    /// System alert sounds offered by the "When Timer Ends" picker.
    static var systemSounds: [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? []
        let list = names.filter { $0.hasSuffix(".aiff") }.map { String($0.dropLast(5)) }.sorted()
        return list.isEmpty ? ["Glass"] : list
    }

    private enum CodingKeys: String, CodingKey {
        case disabled, gridPoint, gridSize, showSeconds, showMilliseconds, soundName, alertSeconds, showInClosedNotch, presets, showRecents
    }

    static let `default` = TimerWidgetSettings()

    var gridSizeType: NookWidget.NookGridSizeType { NookWidget.timer.gridSizeType }
}

extension TimerWidgetSettings {
    // Tolerant decoding: a missing or undecodable field keeps its default (values stored before
    // the timer pass lack the newer keys). In an extension, so the memberwise initializer stays.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.decodeSetting(.disabled, into: &disabled)
        c.decodeSetting(.gridPoint, into: &gridPoint)
        c.decodeSetting(.gridSize, into: &gridSize)
        c.decodeSetting(.showSeconds, into: &showSeconds)
        c.decodeSetting(.showMilliseconds, into: &showMilliseconds)
        c.decodeSetting(.soundName, into: &soundName)
        c.decodeSetting(.alertSeconds, into: &alertSeconds)
        c.decodeSetting(.showInClosedNotch, into: &showInClosedNotch)
        // a malformed list keeps the defaults instead of failing the whole settings value
        c.decodeSetting(.presets, into: &presets)
        presets = TimerPreset.normalized(presets)
        c.decodeSetting(.showRecents, into: &showRecents)
    }
}

// MARK: - Presets

/// One preset slot of the Timer widget: a duration and an optional label.
struct TimerPreset: Codable, Hashable {
    var seconds: Int
    var label: String = ""

    /// The widget has exactly this many preset slots.
    static let slotCount = 5
    /// The longest duration the creator's wheels can show (23:59:59).
    static let maxSeconds = 23 * 3600 + 59 * 60 + 59

    /// "Restore Defaults": 1m, 5m, 10m, 25m, 1h.
    static let defaults: [TimerPreset] = [60, 300, 600, 1500, 3600].map { TimerPreset(seconds: $0) }

    init(seconds: Int, label: String = "") {
        self.seconds = seconds
        self.label = label
    }

    // tolerant: missing keys keep the defaults
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seconds = min(max((try? c.decodeIfPresent(Int.self, forKey: .seconds)) ?? 0, 0), Self.maxSeconds)
        label = (try? c.decodeIfPresent(String.self, forKey: .label)) ?? ""
    }

    /// Exactly `slotCount` slots: the first ones of `list` (an older variable-length list keeps
    /// its first five), padded with the defaults.
    static func normalized(_ list: [TimerPreset]) -> [TimerPreset] {
        var result = Array(list.prefix(slotCount))
        while result.count < slotCount { result.append(defaults[result.count]) }
        return result
    }

    var hours: Int { seconds / 3600 }
    var minutes: Int { (seconds % 3600) / 60 }
    var secondsPart: Int { seconds % 60 }
}
