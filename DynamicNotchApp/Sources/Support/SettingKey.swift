// UserDefaults key names of DynamicNotch's own settings, for `SettingsStore` (SettingsStorage.swift,
// a symlink to FanControlUI's Storage/SettingsStore.swift: the store implementation is shared,
// the key names are the app's). Formerly part of the FanControl drop-in storage file.
// Other files add keys with `extension SettingKey`.

/// UserDefaults key names of every stored setting. These strings are the
/// on-disk identity of the user's settings: never rename one (the names are
/// the former `Defaults.Keys` names, unchanged).
enum SettingKey {
    // DynamicNotch settings structs (DynamicNotchApp/Sources/Support/SettingsKeys.swift)
    static let generalSettings = "generalSettings"
    static let gestureControlSettings = "gestureControlSettings"
    static let liquidGlassSettings = "liquidGlassSettings"
    static let liquidBasicSettings = "liquidBasicSettings"
    static let liveActivitiesSettings = "liveActivitiesSettings"
    static let batteryLiveActivitySettings = "batteryLiveActivitySettings"
    static let calendarLiveActivitySettings = "calendarLiveActivitySettings"
    static let mediaLiveActivitySettings = "mediaLiveActivitySettings"
    static let dropAreaSettings = "dropAreaSettings"
    static let traySettings = "traySettings"
    static let nookSettings = "nookSettings"
    static let calendarWidgetSettings = "calendarWidgetSettings"
    static let mediaWidgetSettings = "mediaWidgetSettings"
    static let mirrorWidgetSettings = "mirrorWidgetSettings"
    static let notesWidgetSettings = "notesWidgetSettings"
    static let quickAppsWidgetSettings = "quickAppsWidgetSettings"
    static let shortcutsWidgetSettings = "shortcutsWidgetSettings"
    static let timerWidgetSettings = "timerWidgetSettings"
    static let clipboardWidgetSettings = "clipboardWidgetSettings"
    static let remindersWidgetSettings = "remindersWidgetSettings"
    // DynamicNotch scalar settings
    static let intro = "intro"
    static let quickAppsPaths = "quickAppsPaths"
    static let shortcutsWidgetSelection = "shortcutsWidgetSelection"
    static let defaultMirrorDevice = "defaultMirrorDevice"
    static let mirrorCameraInputWhenAvail = "mirrorCameraInputWhenAvail"
    // Fan Control keys ("fanControlWidgetSettings", "fanControlGeneralSettings",
    // "fanControlThresholdSettings", "fanControlTemperatureWidgetSettings") belong to
    // FanControlUI (`FanControlSettingKey<…>.name`); the host's typed keys for the two it reads
    // itself are in FanControl-Patches.swift.
}
