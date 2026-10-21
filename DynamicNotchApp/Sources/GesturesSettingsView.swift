// Settings ▸ Gestures: a form over GestureControlSettings.
import SwiftUI

struct GesturesSettingsView: View {
    @StoredSetting(.gestureControlSettings) private var settings: GestureControlSettings

    var body: some View {
        SettingsForm {
            Toggle("Allow gestures", isOn: $settings.allowGestures)
            Toggle("Control media", isOn: $settings.controlMedia)
            Toggle("Open/close the notch", isOn: $settings.controlOpenState)
            Toggle("Invert media gestures", isOn: $settings.invertMediaGestures)
        }
    }
}
