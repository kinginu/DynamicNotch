// Settings ▸ General: a form over GeneralSettings;
//   the login item is registered with SMAppService.
import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @StoredSetting(.generalSettings) private var settings: GeneralSettings

    var body: some View {
        SettingsForm {
            Toggle("Launch at login", isOn: launchAtLogin)
            Toggle("Animations", isOn: $settings.animationEnabled)
            Toggle("Liquid glass", isOn: $settings.liquidGlass)
            Toggle("Sound effects", isOn: $settings.soundFxEnabled)
            Toggle("Haptic feedback", isOn: $settings.hapticFeedbackEnabled)
            Toggle("Disable DynamicNotch", isOn: $settings.disabled)
            Slider(value: $settings.autoHideNotchTime, in: 0.5...10) { Text("Auto-hide delay") }
        }
        // The login item is the source of truth (the user can remove it in System Settings).
        .onAppear { settings.launchAtLogin = Self.isLoginItemOn }
    }

    // the stored flag alone did nothing (app review 2026-10-20): register / unregister
    //   the app as a login item with SMAppService (macOS 13+). If a shared LoginItemManager lands,
    //   route these calls through it.
    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { settings.launchAtLogin },
            set: { on in
                do {
                    if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {
                    NSLog("[GeneralSettings] login item %@ failed: %@", on ? "register" : "unregister", String(describing: error))
                }
                settings.launchAtLogin = Self.isLoginItemOn
            }
        )
    }

    private static var isLoginItemOn: Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval: return true
        default: return false
        }
    }
}
