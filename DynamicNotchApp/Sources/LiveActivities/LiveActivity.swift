import SwiftUI

/// Something shown beside the camera housing while the notch is closed.
///
/// Producers request an activity through `ActiveLiveActivitiesManager`; `LiveActivityCenter`
/// filters the requests by the user's settings and picks the one that holds the closed notch.
/// Everything static about a case — identifier, symbol, name, priority, width, settings gate — is
/// in its `LiveActivityDescriptor` (LiveActivityDescriptor.swift).
enum LiveActivity: MetaInfo, CaseIterable, Codable, Hashable, Identifiable, RawRepresentable {
    case media
    case tray
    case calendar
    case updateAvailable
    case bluetoothDevice
    case battery
    case timerExpired
    case pomodoro
    case volume
    case nextUp
    case keepAwake
    case hud // F5: volume / brightness / keyboard-backlight HUD (HUDMonitor)
    #if canImport(FanControlKit) // fan-control-integration.md (f)
    case fanAlert
    #endif

    /// Persisted identifier (`LiveActivitiesSettings.disabledActivities`); never change one.
    var id: String { descriptor.id }
    var icon: String { descriptor.icon }
    var name: String { descriptor.name }
    var isConfigurable: Bool { descriptor.isConfigurable }

    var rawValue: String { id }

    init?(rawValue: String) {
        guard let activity = Self.allCases.first(where: { $0.id == rawValue }) else { return nil }
        self = activity
    }

    /// Every activity, highest priority first.
    static let byPriority: [LiveActivity] = allCases.sorted { $0.descriptor.priority > $1.descriptor.priority }
}
