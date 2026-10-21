// Settings of the Audio widget (2026-10-20). Key: "audioDevicesWidgetSettings" (declared
// below; pattern: SettingsUI/SettingsDecoding.swift).
import Foundation

struct AudioDevicesWidgetSettings: Preferences, WidgetPrefs, Codable, Equatable, Hashable {
    /// Show the input (microphone) column next to the outputs.
    var showInputs: Bool = true
    /// Show the output volume slider and mute button below the outputs.
    var showVolume: Bool = true
    /// Show the input level meter below the inputs (only while the widget is visible, and only when
    /// microphone access is granted; otherwise the meter is hidden).
    var showInputLevel: Bool = true

    static let `default` = AudioDevicesWidgetSettings()

    var gridSizeType: NookWidget.NookGridSizeType { .small }   // width: AudioDevicesWidgetLayout

    init() {}

    // Tolerant decoding: a missing or undecodable field keeps its default.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.decodeSetting(.showInputs, into: &showInputs)
        c.decodeSetting(.showVolume, into: &showVolume)
        c.decodeSetting(.showInputLevel, into: &showInputLevel)
    }

    private enum CodingKeys: String, CodingKey {
        case showInputs, showVolume, showInputLevel
    }
}

extension SettingKey {
    static let audioDevicesWidgetSettings = "audioDevicesWidgetSettings"
}

extension StoredKeys {
    static let audioDevicesWidgetSettings = Key<AudioDevicesWidgetSettings>(SettingKey.audioDevicesWidgetSettings, default: .default)
}
