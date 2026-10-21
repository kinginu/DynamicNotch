// Settings ▸ Live Activities: General / Customize sub-tabs.
import SwiftUI

struct LiveActivitiesSettingsView: View {
    /// remembered across openings (was @State)
    @AppStorage("liveActivitiesSettingsTab") private var selection: Int = 0

    var body: some View {
        // a segmented control rather than a nested TabView (the native Settings scene would
        //   hoist a TabView into its toolbar; SettingsSubTabs in SettingsRootView.swift)
        SettingsSubTabs(selection: $selection, tabs: [(0, "General"), (1, "Customize")]) { tab in
            if tab == 0 {
                LiveActivitiesGeneralSettingsTabView()
            } else {
                LiveActivitiesCustomizeSettingsTabView()
            }
        }
    }
}