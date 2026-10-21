// Stored-setting keys of the Mirror (camera) widget, read by CameraManager.
import Foundation

extension StoredKeys {
    /// uniqueID of the camera last selected for the Mirror widget.
    static let defaultMirrorDevice = Key<String>(SettingKey.defaultMirrorDevice, default: "")
    /// Mirror the camera input when the connection supports it.
    static let mirrorCameraInputWhenAvail = Key<Bool>(SettingKey.mirrorCameraInputWhenAvail, default: true)
}
