// Environment key of ClipboardWidgetSettings (same pattern as the other *WidgetSettingsKey
// types; bridged to `SettingsStore[.clipboardWidgetSettings]` in Support/Ext-C.swift).
import SwiftUI

struct ClipboardWidgetSettingsKey: EnvironmentKey {
    static let defaultValue: ClipboardWidgetSettings = ClipboardWidgetSettings()
}
