// Settings ▸ Live Activities ▸ Customize: a segmented picker over the activities that have options, showing that activity's settings.
import SwiftUI

struct LiveActivitiesCustomizeSettingsTabView: View {
    @State private var selection: LiveActivity = .media

    private let activities: [LiveActivity] = [.media, .battery, .calendar, .tray, .hud] // F5: + .hud

    var body: some View {
        VStack(spacing: 4) {
            Picker("Activity", selection: $selection) {
                ForEach(activities) { activity in
                    Text(LocalizedStringKey(activity.name)).tag(activity)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .frame(maxWidth: .infinity)   // centred under the sub-tab control (native Settings window)
            .padding(.top, 8)

            Group {
                switch selection {
                case .media: MediaLiveAcitivitySettingsView()
                case .battery: BatteryLiveActivitySettingsView()
                case .calendar: CalendarLiveActivitySettingsView()
                case .tray: TrayLiveActivitySettingsView()
                case .hud: HUDSettingsView() // F5:
                default: NoOptionsSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}
