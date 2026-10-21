// Settings of the battery live activity (Live Activities ▸ Customize): a form over
//   BatteryLiveActivitySettings.
import SwiftUI

struct BatteryLiveActivitySettingsView: View {
    @StoredSetting(.batteryLiveActivitySettings) private var settings: BatteryLiveActivitySettings

    var body: some View {
        SettingsForm {
            Toggle("Enabled", isOn: $settings.enabled)
            Toggle("Show percentage", isOn: $settings.showPercentage)
            Toggle("Show when charging starts", isOn: $settings.showChargingStatus)
            Toggle("Show while the battery is low (20% or less)", isOn: $settings.lowPowerAlert)
            Toggle("Hide when fully charged", isOn: $settings.autoHideWhenFull)
        }
    }
}
