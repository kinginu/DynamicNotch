// Settings pane of a widget / live activity without options.
import SwiftUI

struct NoOptionsSettingsView: View {
    var body: some View {
        SettingsForm {
            Text("No options available")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}
