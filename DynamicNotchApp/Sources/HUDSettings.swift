// F5 (2026-10-20): settings of the volume / brightness / keyboard-backlight HUD shown as the
// `.hud` closed-notch live activity (HUDMonitor, HUDLiveActivityView, docs/hud.md).
//
// The master switch is the existing "Volume & brightness HUD" toggle in Settings ▸ Live Activities ▸
// General (`LiveActivitiesSettings.enableVolumeBrightness`); these are the per-kind switches and the
// key-event option, stored by SettingsStore under "hudSettings" (key declared here).
import Foundation
import SwiftUI
import AppKit

struct HUDSettings: Preferences, Codable, Equatable, Hashable {
    /// Show the HUD when the output volume or mute changes.
    var showVolume: Bool = true
    /// Show the HUD when the built-in display's brightness changes.
    var showBrightness: Bool = true
    /// Show the HUD for the keyboard-backlight (illumination) keys, on keyboards that have them.
    var showKeyboardBacklight: Bool = true
    /// Watch the media keys (volume / brightness / illumination). Needs Input Monitoring for the
    /// event tap; without it a global NSEvent monitor is used (see docs/hud.md). When off, only the
    /// CoreAudio volume observer runs (brightness and the keyboard backlight need the keys).
    var useMediaKeys: Bool = true

    init() {}

    // Tolerant decoding: keys added later fall back to their defaults instead of resetting.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showVolume = try c.decodeIfPresent(Bool.self, forKey: .showVolume) ?? true
        showBrightness = try c.decodeIfPresent(Bool.self, forKey: .showBrightness) ?? true
        showKeyboardBacklight = try c.decodeIfPresent(Bool.self, forKey: .showKeyboardBacklight) ?? true
        useMediaKeys = try c.decodeIfPresent(Bool.self, forKey: .useMediaKeys) ?? true
    }

    private enum CodingKeys: String, CodingKey {
        case showVolume, showBrightness, showKeyboardBacklight, useMediaKeys
    }

    func shows(_ kind: HUDMonitor.Kind) -> Bool {
        switch kind {
        case .volume: return showVolume
        case .brightness: return showBrightness
        case .keyboardBacklight: return showKeyboardBacklight
        }
    }
}

extension StoredKeys {
    static let hudSettings = Key<HUDSettings>("hudSettings", default: .init())
}

// MARK: - Settings pane (Settings ▸ Live Activities ▸ Customize ▸ HUD)

struct HUDSettingsView: View {
    @StoredSetting(.hudSettings) private var settings
    @StoredSetting(.liveActivitiesSettings) private var liveSettings

    private var monitor: HUDMonitor { .shared }

    var body: some View {
        SettingsForm {
            Section {
                Toggle("Volume & brightness HUD", isOn: $liveSettings.enableVolumeBrightness)
            } footer: {
                Text("Shows a short HUD in the closed notch when the volume, display brightness or keyboard backlight changes.")
                    .settingsFootnote()
            }

            Section("Show for") {
                Toggle(isOn: $settings.showVolume) {
                    Label("Volume", systemImage: "speaker.wave.2.fill")
                }
                Toggle(isOn: $settings.showBrightness) {
                    Label("Display brightness", systemImage: "sun.max.fill")
                }
                Toggle(isOn: $settings.showKeyboardBacklight) {
                    Label("Keyboard backlight", systemImage: "light.max")
                }
            }
            .disabled(!liveSettings.enableVolumeBrightness)

            Section {
                Toggle("Watch the volume and brightness keys", isOn: $settings.useMediaKeys)
                PermissionStatusRow(
                    kind: .inputMonitoring, showsTitle: true,
                    granted: "Media keys are read with a listen-only event tap.",
                    notDetermined: "Not allowed. Volume changes still show; the keys may not.",
                    denied: "Not allowed. Volume changes still show; the keys may not.",
                    allowTitle: "Request Access")
            } header: {
                Text("Keys")
            } footer: {
                Text("With Input Monitoring the volume, brightness and keyboard-backlight keys are read by a listen-only event tap. Without it volume changes still show; the brightness keys work only if macOS delivers them to the app's global event monitor.")
                    .settingsFootnote()
            }
            .disabled(!liveSettings.enableVolumeBrightness)

            Section("Sources") {
                LabeledContent("Volume", value: monitor.volumeSourceDescription)
                LabeledContent("Display brightness", value: monitor.brightnessSourceDescription)
                LabeledContent("Keyboard backlight", value: monitor.keyboardSourceDescription)
                LabeledContent("Media keys", value: monitor.keySourceDescription)
            }

            Section {
                Text("The system's own volume and brightness HUD still appears: macOS has no public API to hide it.")
                    .settingsFootnote()
            }
        }
        .onAppear { monitor.refreshPermissions() }
    }
}
