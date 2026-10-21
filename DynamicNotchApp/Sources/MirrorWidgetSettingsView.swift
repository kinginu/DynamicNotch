// Settings ▸ Nook ▸ Widgets ▸ Mirror: the camera (CameraManager.selectedDevice,
// persisted as `defaultMirrorDevice`), mirroring, frame and auto-open (MirrorWidgetSettings).
import SwiftUI
import AVFoundation

struct MirrorWidgetSettingsView: View {
    @StoredSetting(.mirrorWidgetSettings) private var settings
    @StoredSetting(.mirrorCameraInputWhenAvail) private var mirrored
    @State private var cameras = CameraManager.shared

    var body: some View {
        SettingsForm {
            Section {
                if cameras.allDevices.isEmpty {
                    Text("No camera found")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Camera", selection: cameraSelection) {
                        ForEach(cameras.allDevices, id: \.uniqueID) { device in
                            Text(device.localizedName).tag(device.uniqueID)
                        }
                    }
                }
                Toggle("Mirror the image", isOn: $mirrored)
                Toggle("Show frame", isOn: $settings.showFrame)
                Toggle("Open camera automatically", isOn: $settings.autoOpen)
            } footer: {
                Text("The camera only runs while the Nook is open. Click the preview to start or stop it.")
                    .settingsFootnote()
            }
        }
    }

    private var cameraSelection: Binding<String> {
        Binding(
            get: { cameras.selectedDevice?.uniqueID ?? "" },
            set: { id in
                cameras.selectedDevice = cameras.allDevices.first { $0.uniqueID == id }
                SettingsStore[.defaultMirrorDevice] = id
            }
        )
    }
}
