import AppKit
import SwiftUI
import SwiftData

/// Root of one screen's notch window: the screen's NotchView with its per-screen state, window
/// geometry, SwiftData container and the environment values the widgets read.
struct RootView: View {
    @State private var viewModel: NotchViewModel
    @State private var settingsPaneIdentifier: String? = nil
    @Namespace private var namespace

    /// Hardware notch size of the screen this view is hosted on.
    private let screenNotchSize: CGSize
    /// This screen's notch state and window geometry (WindowsManager.DisplayKit).
    private let notchState: DynamicNotchState
    private let geometry: NotchWindowGeometry

    var body: some View {
        NotchView(viewModel: viewModel)
            .environment(\.dynamicNotchState, notchState)
            .environment(\.notchWindowGeometry, geometry)
            .nookModelContainer() // Notes widget (@Query)
            .environment(\.settingsPaneIdentifier, settingsPaneIdentifier)
            .environment(\.namespaceID, namespace)
            .environment(\.showNotch, true)
            .environment(\.hideNotch, false)
            .environment(\.notchSize, screenNotchSize)
            .environment(\.notchState, viewModel.notchState)
            .environment(\.expandedNoteState, ExpandedNoteManager())
            .environment(\.generalSettings, GeneralSettings.defaultValue)
            .environment(\.liquidGlassSettings, LiquidGlassSettings.defaultValue)
            .environment(\.gestureControlSettings, GestureControlSettings.defaultValue)
            .environment(\.liveActivitiesSettings, LiveActivitiesSettings.defaultValue)
            .environment(\.nookSettings, NookSettings.defaultValue)
            .environment(\.traySettings, TraySettings.defaultValue)
            .environment(\.dropAreaSettings, DropAreaSettings.defaultValue)
            .environment(\.showIndicator, true)
            .environment(\.indicatorVisible, true)
            .environment(\.mediaLiveActivitySettings, MediaLiveActivitySettings.defaultValue)
            .environment(\.calendarLiveActivitySettings, CalendarLiveActivitySettings.defaultValue)
            .environment(\.mediaWidgetSettings, MediaWidgetSettings.defaultValue)
            .environment(\.shortcutsWidgetSettings, ShortcutsWidgetSettings.defaultValue)
            .environment(\.mirrorWidgetSettings, MirrorWidgetSettings.defaultValue)
            .environment(\.calendarWidgetSettings, CalendarWidgetSettings.defaultValue)
            .environment(\.notesWidgetSettings, NotesWidgetSettings.defaultValue)
            .environment(\.quickAppsWidgetSettings, QuickAppsWidgetSettings.defaultValue)
            .environment(\.timerWidgetSettings, TimerWidgetSettings.defaultValue)
    }

    init(screenNotchSize: CGSize = CGSize(width: 200, height: 32),
         notchState: DynamicNotchState = .shared, geometry: NotchWindowGeometry = NotchWindowGeometry(),
         window: NSWindow? = nil) {
        self.screenNotchSize = screenNotchSize
        self.notchState = notchState
        self.geometry = geometry
        let intro = SettingsStore[.intro]

        let vm = NotchViewModel()
        vm.showIntro = intro
        vm.screenNotchState = notchState
        vm.notchWindow = window
        #if DEBUG
        if let window { NotchViewModel.debugByWindow.setObject(vm, forKey: window) }
        #endif
        _viewModel = State(initialValue: vm)
    }
}