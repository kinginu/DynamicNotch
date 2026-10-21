// Settings helpers: stored-setting keys of the
// settings structs (SettingsStore, FanControl/Sources/FanControlUI/Storage/SettingsStore.swift)
// and small shims (colours) needed by the settings views.
import Foundation
import AppKit
import SwiftUI

// MARK: - Stored-setting keys

// One key per settings struct, named after the struct in
// lowerCamelCase (same convention as `SettingsStore[.fanControlWidgetSettings]`).
extension StoredKeys {
    static let generalSettings = Key<GeneralSettings>(SettingKey.generalSettings, default: .init())
    static let gestureControlSettings = Key<GestureControlSettings>(SettingKey.gestureControlSettings, default: .init())
    static let liquidGlassSettings = Key<LiquidGlassSettings>(SettingKey.liquidGlassSettings, default: .init())
    static let liquidBasicSettings = Key<LiquidBasicSettings>(SettingKey.liquidBasicSettings, default: .init())
    static let liveActivitiesSettings = Key<LiveActivitiesSettings>(SettingKey.liveActivitiesSettings, default: .init())
    static let batteryLiveActivitySettings = Key<BatteryLiveActivitySettings>(SettingKey.batteryLiveActivitySettings, default: .init())
    static let calendarLiveActivitySettings = Key<CalendarLiveActivitySettings>(SettingKey.calendarLiveActivitySettings, default: .init())
    static let dropAreaSettings = Key<DropAreaSettings>(SettingKey.dropAreaSettings, default: .init())
    static let traySettings = Key<TraySettings>(SettingKey.traySettings, default: .init())
    static let nookSettings = Key<NookSettings>(SettingKey.nookSettings, default: .init())
    static let calendarWidgetSettings = Key<CalendarWidgetSettings>(SettingKey.calendarWidgetSettings, default: .init())
    static let mirrorWidgetSettings = Key<MirrorWidgetSettings>(SettingKey.mirrorWidgetSettings, default: .init())
    static let notesWidgetSettings = Key<NotesWidgetSettings>(SettingKey.notesWidgetSettings, default: .init())
    static let quickAppsWidgetSettings = Key<QuickAppsWidgetSettings>(SettingKey.quickAppsWidgetSettings, default: .init())
    static let shortcutsWidgetSettings = Key<ShortcutsWidgetSettings>(SettingKey.shortcutsWidgetSettings, default: .init())
    static let timerWidgetSettings = Key<TimerWidgetSettings>(SettingKey.timerWidgetSettings, default: .init())
    static let clipboardWidgetSettings = Key<ClipboardWidgetSettings>(SettingKey.clipboardWidgetSettings, default: .init())
    static let remindersWidgetSettings = Key<RemindersWidgetSettings>(SettingKey.remindersWidgetSettings, default: .init())
    static let systemStatsWidgetSettings = Key<SystemStatsWidgetSettings>(SettingKey.systemStatsWidgetSettings, default: .init())
    static let calculatorWidgetSettings = Key<CalculatorWidgetSettings>(SettingKey.calculatorWidgetSettings, default: .init())
    // Weather widget (2026-10-20); key name literal (FanControl's SettingKey list is not ours to extend)
    static let weatherWidgetSettings = Key<WeatherWidgetSettings>("weatherWidgetSettings", default: .init())
    // Keep Awake widget (2026-10-20); key name literal (FanControl's SettingKey list is not ours to extend)
    static let keepAwakeWidgetSettings = Key<KeepAwakeWidgetSettings>("keepAwakeWidgetSettings", default: .init())
    static let colorPickerWidgetSettings = Key<ColorPickerWidgetSettings>(SettingKey.colorPickerWidgetSettings, default: .init())
}

// Color Picker / Calculator widgets (2026-10-20): key names declared here (FanControl's SettingKey
// list is not ours to edit).
extension SettingKey {
    static let colorPickerWidgetSettings = "colorPickerWidgetSettings"
    static let calculatorWidgetSettings = "calculatorWidgetSettings"
}

// MARK: - Colours

// The fine-tuning backdrop colour (a deep violet-black). Formerly a catalog colour; now a literal so
// the app ships no asset catalog.
extension Color {
    static let fineTuningBG = Color(.displayP3, red: 0.0902, green: 0.0588, blue: 0.1020)
}
