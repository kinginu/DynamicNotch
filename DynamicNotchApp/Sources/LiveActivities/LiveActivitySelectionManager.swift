import Foundation
import Observation

/// Picks the activity that holds the closed notch when several are requested.
@Observable
class LiveActivitySelectionManager {
    static let shared = LiveActivitySelectionManager()

    /// Highest priority first (`LiveActivityDescriptor.priority`).
    var activitiesByPriority: [LiveActivity] = LiveActivity.byPriority

    func sortByPriority() {
        activitiesByPriority.sort { $0.descriptor.priority > $1.descriptor.priority }
    }

    /// The highest-priority activity in `activeActivities` — except that on battery power the
    /// battery activity (low battery) wins over everything that does not outrank the battery rule
    /// (`outranksBatteryRule`: safety alerts such as the FanControl alert, and the HUD).
    func selectActivity(
        from activeActivities: Set<LiveActivity>,
        batteryStatus: PowerMonitor.BatteryStatus?
    ) -> LiveActivity? {
        Self.select(from: activeActivities, ordered: activitiesByPriority,
                    onBattery: batteryStatus.map { !$0.isCharging } ?? false)
    }

    /// Pure selection rule (unit-tested): the first requested activity in `ordered`, unless the
    /// Mac runs on battery with `.battery` requested — then `.battery`, unless the top activity
    /// outranks the battery rule.
    static func select(from activeActivities: Set<LiveActivity>, ordered: [LiveActivity], onBattery: Bool) -> LiveActivity? {
        let top = ordered.first { activeActivities.contains($0) }
        if let top, top.outranksBatteryRule { return top }
        if onBattery, activeActivities.contains(.battery) { return .battery }
        return top
    }
}

extension LiveActivity {
    /// Shown even while the low-battery activity holds the notch on battery power: safety alerts
    /// (descriptor gate `.always`, e.g. the FanControl overheating / fan-stalled alert) and the
    /// HUD (F5: a key-press response).
    var outranksBatteryRule: Bool {
        if self == .hud { return true }
        if case .always = descriptor.gate { return true }
        return false
    }
}
