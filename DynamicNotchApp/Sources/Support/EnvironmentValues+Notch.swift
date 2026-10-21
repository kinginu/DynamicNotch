// SwiftUI environment values of the notch UI (`@Environment(\.x)` / `.environment(\.x, …)`).
// Keys declared in their own *Key.swift files are reused here; the ones below are local to this file.
//
// Class-typed defaults are computed (`{ nil }`) so the keys hold no shared global state.
import AppKit
import SwiftUI

struct DynamicNotchStateEnvKey: EnvironmentKey { static var defaultValue: DynamicNotchState? { nil } }
struct NotchModeEnvKey: EnvironmentKey { static let defaultValue: DynamicNotchState.NotchMode? = nil }
struct NotchStateEnvKey: EnvironmentKey { static var defaultValue: NotchState? { nil } }
struct NotchViewModelEnvKey: EnvironmentKey { static var defaultValue: NotchViewModel? { nil } }
struct NoteDocumentEnvKey: EnvironmentKey { static let defaultValue: NoteDocument? = nil }
struct PowerMonitorEnvKey: EnvironmentKey { static var defaultValue: PowerMonitor? { nil } }
struct DateEnvKey: EnvironmentKey { static let defaultValue: Date = Date() }
struct IndicatorEnvKey: EnvironmentKey { static var defaultValue: Indicator? { nil } }
struct LiveActivityEnvKey: EnvironmentKey { static let defaultValue: LiveActivity? = nil }
struct ExpandedNoteStateEnvKey: EnvironmentKey { static var defaultValue: ExpandedNoteManager? { nil } }
struct IndicatorVisibleEnvKey: EnvironmentKey { static let defaultValue: Bool = true }
struct ShowNotchEnvKey: EnvironmentKey { static let defaultValue: Bool = true }
struct SettingsPaneIdentifierEnvKey: EnvironmentKey { static let defaultValue: String? = nil }

extension EnvironmentValues {
    var calendarLiveActivitySettings: CalendarLiveActivitySettings {
        get { self[CalendarLiveActivitySettingsKey.self] }
        set { self[CalendarLiveActivitySettingsKey.self] = newValue }
    }
    var calendarWidgetSettings: CalendarWidgetSettings {
        get { self[CalendarWidgetSettingsKey.self] }
        set { self[CalendarWidgetSettingsKey.self] = newValue }
    }
    var cameraManager: CameraManager? {
        get { self[CameraManagerKey.self] }
        set { self[CameraManagerKey.self] = newValue }
    }
    var closeNotch: () -> Void {
        get { self[CloseNotchKey.self] }
        set { self[CloseNotchKey.self] = newValue }
    }
    var closeWindow: () -> Void {
        get { self[CloseWindowKey.self] }
        set { self[CloseWindowKey.self] = newValue }
    }
    var displayKitId: UInt32? {
        get { self[DisplayKitIdKey.self] }
        set { self[DisplayKitIdKey.self] = newValue }
    }
    var dropAreaSettings: DropAreaSettings {
        get { self[DropAreaSettingsKey.self] }
        set { self[DropAreaSettingsKey.self] = newValue }
    }
    var dynamicNotch: DynamicNotchState? {
        get { self[DynamicNotchKey.self] }
        set { self[DynamicNotchKey.self] = newValue }
    }
    var enableQuickPeek: Bool {
        get { self[EnableQuickPeekKey.self] }
        set { self[EnableQuickPeekKey.self] = newValue }
    }
    var enableTextEditingForWindowWith: (NSWindow?) -> Void {
        get { self[EnableTextEditingForWindowWithKey.self] }
        set { self[EnableTextEditingForWindowWithKey.self] = newValue }
    }
    var expandedNoteManager: ExpandedNoteManager? {
        get { self[ExpandedNoteManagerKey.self] }
        set { self[ExpandedNoteManagerKey.self] = newValue }
    }
    var generalSettings: GeneralSettings {
        get { self[GeneralSettingsKey.self] }
        set { self[GeneralSettingsKey.self] = newValue }
    }
    var gestureControlSettings: GestureControlSettings {
        get { self[GestureControlSettingsKey.self] }
        set { self[GestureControlSettingsKey.self] = newValue }
    }
    var getNow: () -> Date {
        get { self[GetNowKey.self] }
        set { self[GetNowKey.self] = newValue }
    }
    var hideNotch: Bool {
        get { self[HideNotchKey.self] }
        set { self[HideNotchKey.self] = newValue }
    }
    var isEditingText: Bool {
        get { self[IsEditingTextKey.self] }
        set { self[IsEditingTextKey.self] = newValue }
    }
    var liquidGlassSettings: LiquidGlassSettings {
        get { self[LiquidGlassSettingsKey.self] }
        set { self[LiquidGlassSettingsKey.self] = newValue }
    }
    var liveActivitiesSettings: LiveActivitiesSettings {
        get { self[LiveActivitiesSettingsKey.self] }
        set { self[LiveActivitiesSettingsKey.self] = newValue }
    }
    var makeKeyWindow: () -> Void {
        get { self[MakeKeyWindowKey.self] }
        set { self[MakeKeyWindowKey.self] = newValue }
    }
    var mediaLiveActivitySettings: MediaLiveActivitySettings {
        get { self[MediaLiveActivitySettingsKey.self] }
        set { self[MediaLiveActivitySettingsKey.self] = newValue }
    }
    var mediaWidgetSettings: MediaWidgetSettings {
        get { self[MediaWidgetSettingsKey.self] }
        set { self[MediaWidgetSettingsKey.self] = newValue }
    }
    var mirrorWidgetSettings: MirrorWidgetSettings {
        get { self[MirrorWidgetSettingsKey.self] }
        set { self[MirrorWidgetSettingsKey.self] = newValue }
    }
    var namespaceID: Namespace.ID? {
        get { self[NamespaceKey.self] }
        set { self[NamespaceKey.self] = newValue }
    }
    var nookSettings: NookSettings {
        get { self[NookSettingsKey.self] }
        set { self[NookSettingsKey.self] = newValue }
    }
    var nookWidgetsWidth: CGFloat {
        get { self[NookWidgetsWidthKey.self] }
        set { self[NookWidgetsWidthKey.self] = newValue }
    }
    var notchSize: CGSize {
        get { self[NotchSizeKey.self] }
        set { self[NotchSizeKey.self] = newValue }
    }
    var notesWidgetSettings: NotesWidgetSettings {
        get { self[NotesWidgetSettingsKey.self] }
        set { self[NotesWidgetSettingsKey.self] = newValue }
    }
    var openNotch: () -> Void {
        get { self[OpenNotchKey.self] }
        set { self[OpenNotchKey.self] = newValue }
    }
    var openSettings: () -> Void {
        get { self[OpenSettingsKey.self] }
        set { self[OpenSettingsKey.self] = newValue }
    }
    var quickAppsWidgetSettings: QuickAppsWidgetSettings {
        get { self[QuickAppsWidgetSettingsKey.self] }
        set { self[QuickAppsWidgetSettingsKey.self] = newValue }
    }
    var resignFirstResponder: () -> Void {
        get { self[ResignFirstResponderKey.self] }
        set { self[ResignFirstResponderKey.self] = newValue }
    }
    var displaySize: CGSize {
        get { self[ScreenSizeKey.self] }
        set { self[ScreenSizeKey.self] = newValue }
    }
    var shortcutsWidgetSettings: ShortcutsWidgetSettings {
        get { self[ShortcutsWidgetSettingsKey.self] }
        set { self[ShortcutsWidgetSettingsKey.self] = newValue }
    }
    var showIndicator: Bool {
        get { self[ShowIndicatorKey.self] }
        set { self[ShowIndicatorKey.self] = newValue }
    }
    var timerWidgetSettings: TimerWidgetSettings {
        get { self[TimerWidgetSettingsKey.self] }
        set { self[TimerWidgetSettingsKey.self] = newValue }
    }
    var tray: Tray? {
        get { self[TrayKey.self] }
        set { self[TrayKey.self] = newValue }
    }
    var traySettings: TraySettings {
        get { self[TraySettingsKey.self] }
        set { self[TraySettingsKey.self] = newValue }
    }
    var updateEditingTextStateFor: (NSWindow?, Bool) -> Void {
        get { self[UpdateEditingTextStateForKey.self] }
        set { self[UpdateEditingTextStateForKey.self] = newValue }
    }
    var dynamicNotchState: DynamicNotchState? {
        get { self[DynamicNotchStateEnvKey.self] }
        set { self[DynamicNotchStateEnvKey.self] = newValue }
    }
    var notchMode: DynamicNotchState.NotchMode? {
        get { self[NotchModeEnvKey.self] }
        set { self[NotchModeEnvKey.self] = newValue }
    }
    var notchState: NotchState? {
        get { self[NotchStateEnvKey.self] }
        set { self[NotchStateEnvKey.self] = newValue }
    }
    var notchViewModel: NotchViewModel? {
        get { self[NotchViewModelEnvKey.self] }
        set { self[NotchViewModelEnvKey.self] = newValue }
    }
    var noteDocument: NoteDocument? {
        get { self[NoteDocumentEnvKey.self] }
        set { self[NoteDocumentEnvKey.self] = newValue }
    }
    var powerMonitor: PowerMonitor? {
        get { self[PowerMonitorEnvKey.self] }
        set { self[PowerMonitorEnvKey.self] = newValue }
    }
    var date: Date {
        get { self[DateEnvKey.self] }
        set { self[DateEnvKey.self] = newValue }
    }
    var indicator: Indicator? {
        get { self[IndicatorEnvKey.self] }
        set { self[IndicatorEnvKey.self] = newValue }
    }
    var liveActivity: LiveActivity? {
        get { self[LiveActivityEnvKey.self] }
        set { self[LiveActivityEnvKey.self] = newValue }
    }
    var expandedNoteState: ExpandedNoteManager? {
        get { self[ExpandedNoteStateEnvKey.self] }
        set { self[ExpandedNoteStateEnvKey.self] = newValue }
    }
    var indicatorVisible: Bool {
        get { self[IndicatorVisibleEnvKey.self] }
        set { self[IndicatorVisibleEnvKey.self] = newValue }
    }
    var showNotch: Bool {
        get { self[ShowNotchEnvKey.self] }
        set { self[ShowNotchEnvKey.self] = newValue }
    }
    var settingsPaneIdentifier: String? {
        get { self[SettingsPaneIdentifierEnvKey.self] }
        set { self[SettingsPaneIdentifierEnvKey.self] = newValue }
    }
}
