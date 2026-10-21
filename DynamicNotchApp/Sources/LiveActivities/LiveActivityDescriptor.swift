import SwiftUI

/// Static description of a live activity: how it is identified and labelled, where it ranks when
/// several want the closed notch, how much room it takes beside the camera housing, and which
/// settings gate it. One per `LiveActivity` case (`LiveActivity.descriptor`).
struct LiveActivityDescriptor {
    /// Width of each side of the closed notch (both sides are equally wide so the camera housing
    /// stays centred).
    enum SideWidth {
        /// Icon-sized content: `max(notch height, 24) + extra`.
        case notchHeight(plus: CGFloat)
        case fixed(CGFloat)
        /// State-dependent width (e.g. a countdown that gains an hours field), from the notch height.
        case custom(@MainActor (_ notchHeight: CGFloat) -> CGFloat)
    }

    /// Which settings must allow the activity before a request for it is shown.
    enum Gate {
        /// A safety alert: shown whatever the Live Activities settings say.
        case always
        /// Settings ▸ Live Activities: the master switch and the activity's own toggle.
        case liveActivitiesSettings
        /// As `liveActivitiesSettings`, plus a switch in the activity's own settings pane.
        case liveActivitiesSettingsAnd(@MainActor (LiveActivityCenter) -> Bool)
    }

    /// Persisted identifier (also `LiveActivity.rawValue`).
    let id: String
    /// SF Symbol.
    let icon: String
    let name: String
    /// Higher wins the closed notch when several activities are requested
    /// (`LiveActivitySelectionManager`).
    let priority: Int
    let sideWidth: SideWidth
    /// Has an on/off toggle in Settings ▸ Live Activities.
    let isConfigurable: Bool
    let gate: Gate

    @MainActor func sideWidth(notchHeight: CGFloat) -> CGFloat {
        switch sideWidth {
        case .notchHeight(let extra): return max(notchHeight, 24) + extra
        case .fixed(let width): return width
        case .custom(let width): return width(notchHeight)
        }
    }
}

extension LiveActivity {
    var descriptor: LiveActivityDescriptor {
        switch self {
        #if canImport(FanControlKit) // fan-control-integration.md (f): fan icon | temperature + title
        case .fanAlert:
            return .init(id: "fanAlert", icon: "fan", name: "Fan Alert", priority: 100,
                         sideWidth: .fixed(132), isConfigurable: false, gate: .always)
        #endif
        case .hud: // F5: icon | level bar (HUDMonitor); below the fan alert, above everything else
            return .init(id: "hud", icon: "slider.horizontal.3", name: "HUD", priority: 95,
                         sideWidth: .custom(HUDLiveActivityView.sideWidth), isConfigurable: false,
                         gate: .liveActivitiesSettings)
        case .timerExpired: // counting: ring | remaining time; ended: bell + label | Stop
            return .init(id: "timerExpired", icon: "timer", name: "Timer Ended", priority: 90,
                         sideWidth: .custom(TimerLiveActivityView.sideWidth), isConfigurable: true,
                         gate: .liveActivitiesSettings)
        case .pomodoro: // Focus widget: same metrics as the timer
            return .init(id: "pomodoro", icon: "brain.head.profile", name: "Focus", priority: 85,
                         sideWidth: .custom { PomodoroInsets.sideWidth(notchHeight: $0) }, isConfigurable: false,
                         gate: .liveActivitiesSettings)
        case .battery: // battery icon | percentage or time remaining
            return .init(id: "batteryStatus", icon: "bolt.fill", name: "Battery", priority: 80,
                         sideWidth: .notchHeight(plus: 18), isConfigurable: true,
                         gate: .liveActivitiesSettingsAnd { $0.batterySettings.enabled })
        case .nextUp: // Next Up widget: calendar symbol | "5 min"
            return .init(id: "nextUp", icon: "clock.badge", name: "Next Up", priority: 70,
                         sideWidth: .notchHeight(plus: 24), isConfigurable: true, gate: .liveActivitiesSettings)
        case .calendar: // calendar symbol | minutes until the start
            return .init(id: "calendar", icon: "calendar", name: "Calendar", priority: 60,
                         sideWidth: .notchHeight(plus: 18), isConfigurable: true,
                         gate: .liveActivitiesSettingsAnd { $0.calendarSettings.isEnabled })
        case .bluetoothDevice:
            return .init(id: "bluetoothDevice", icon: "airpods", name: "Bluetooth", priority: 50,
                         sideWidth: .notchHeight(plus: 8), isConfigurable: false, gate: .liveActivitiesSettings)
        case .volume:
            return .init(id: "volume", icon: "speaker.wave.2.fill", name: "Volume", priority: 40,
                         sideWidth: .notchHeight(plus: 8), isConfigurable: false, gate: .liveActivitiesSettings)
        case .media: // artwork | visualizer
            return .init(id: "media", icon: "music.note", name: "Media", priority: 30,
                         sideWidth: .notchHeight(plus: 8), isConfigurable: true, gate: .liveActivitiesSettings)
        case .tray: // tray icon | file count
            return .init(id: "tray", icon: "tray.fill", name: "Files Tray", priority: 20,
                         sideWidth: .notchHeight(plus: 8), isConfigurable: true, gate: .liveActivitiesSettings)
        case .updateAvailable:
            return .init(id: "updateAvailable", icon: "arrow.down.circle", name: "New Update", priority: 10,
                         sideWidth: .notchHeight(plus: 8), isConfigurable: false, gate: .liveActivitiesSettings)
        case .keepAwake: // Keep Awake widget: cup | remaining time
            return .init(id: "keepAwake", icon: "cup.and.saucer.fill", name: "Keep Awake", priority: 0,
                         sideWidth: .custom(KeepAwakeLiveActivityView.sideWidth), isConfigurable: false,
                         gate: .liveActivitiesSettings)
        }
    }
}
