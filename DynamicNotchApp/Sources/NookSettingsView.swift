// Settings ▸ Nook: General / Widgets / Drop Area sub-tabs.
import SwiftUI

struct NookSettingsView: View {
    // tab selection lives in NookSettingsNavigation (Support/Ext-A.swift) so the
    //   notch's "Open Settings" buttons can jump straight to the Widgets tab.
    @State private var navigation = NookSettingsNavigation.shared

    var body: some View {
        // ScrollView wrapper dropped; Widgets tab added — WidgetsSettingsTabView is
        //   otherwise unreachable. The original nested TabView became a segmented control
        //   (SettingsSubTabs): the native Settings scene would hoist a nested TabView into its toolbar.
        SettingsSubTabs(selection: $navigation.tab, tabs: [
            (.general, "General"), (.widgets, "Widgets"), (.dropArea, "Drop Area"),
        ]) { tab in
            switch tab {
            case .general: NookGeneralSettingsTabView()
            case .widgets: WidgetsSettingsTabView()
            case .dropArea: DropAreaGeneralSettingsTabView()
            }
        }
    }
}
