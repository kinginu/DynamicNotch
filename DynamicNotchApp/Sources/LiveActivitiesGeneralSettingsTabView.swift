// Settings ▸ Live Activities ▸ General: a master switch plus one switch per user-configurable activity (stored as
//   LiveActivitiesSettings.disabledActivities).
import SwiftUI
struct LiveActivitiesGeneralSettingsTabView: View {
    @StoredSetting(.liveActivitiesSettings) private var settings

    /// Activities the user can switch off (system-driven / safety ones are not listed).
    static let configurable: [LiveActivity] = [.media, .battery, .calendar, .nextUp, .tray, .timerExpired]

    var body: some View {
        SettingsForm {
            Section {
                Toggle("Show live activities in the closed notch", isOn: $settings.enabled)
                Toggle("Volume & brightness HUD", isOn: $settings.enableVolumeBrightness)
            } footer: {
                Text("Live activities appear beside the camera housing while the notch is closed.")
                    .settingsFootnote()
            }

            Section("Activities") {
                ForEach(Self.configurable) { activity in
                    Toggle(isOn: binding(for: activity)) {
                        Label {
                            Text(LocalizedStringKey(activity.name))
                        } icon: {
                            Image(systemName: activity.icon)
                        }
                    }
                }
            }
            .disabled(!settings.enabled)
        }
    }

    private func binding(for activity: LiveActivity) -> Binding<Bool> {
        Binding(
            get: { !settings.disabledActivities.contains(activity.rawValue) },
            set: { on in
                if on { settings.disabledActivities.remove(activity.rawValue) }
                else { settings.disabledActivities.insert(activity.rawValue) }
            }
        )
    }
}
