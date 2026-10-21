// Settings ▸ Liquid Glass. The original (sindresorhus/Settings) had Basic /
//   Advanced tab buttons over BasicGlassTab / AdvancedGlassTab; here a segmented control
//   (SettingsSubTabs) above one grouped form (BasicGlassTab / AdvancedGlassTab are not used here).
import SwiftUI

struct LiquidSettingsView: View {
    @State private var selection: Int = 0
    @StoredSetting(.liquidBasicSettings) private var basic

    var body: some View {
        SettingsSubTabs(selection: $selection, tabs: [(0, "Basic"), (1, "Advanced")]) { tab in
            SettingsForm {
                Section {
                    if tab == 0 {
                        Slider(value: $basic.field08, in: 0...1) { Text("Blur") }
                        Slider(value: $basic.field10, in: 0...1) { Text("Depth") }
                        Slider(value: $basic.field18, in: 0...1) { Text("Refraction") }
                        Slider(value: $basic.field20, in: 0...1) { Text("Highlight") }
                    } else {
                        Slider(value: $basic.field28, in: 0...1) { Text("Edge") }
                        Slider(value: $basic.field30, in: 0...1) { Text("Dispersion") }
                        Slider(value: $basic.field38, in: 0...1) { Text("Specular") }
                        Toggle("Enabled", isOn: $basic.field40)
                    }
                }
            }
        }
    }
}
