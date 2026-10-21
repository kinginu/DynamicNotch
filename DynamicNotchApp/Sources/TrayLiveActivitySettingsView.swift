// Settings for the "Files Tray" live activity (Live Activities ▸ Customize).
import SwiftUI

struct TrayLiveActivitySettingsView: View {
    @StoredSetting(.traySettings) private var settings: TraySettings

    var body: some View {
        SettingsForm {
            Toggle("Show while the tray has files", isOn: $settings.showLiveActivity)
        }
        .onChange(of: settings.showLiveActivity) { _, _ in Tray.shared.updateLiveActivity() }
    }
}
