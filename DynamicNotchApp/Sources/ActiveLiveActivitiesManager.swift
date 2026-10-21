import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

/// Set of live activities currently shown in the closed notch.
///
/// Producers (MediaManager, LiveActivitiesStartup's battery/calendar/timer monitors, the tray,
/// fan-control-integration.md (f)) call `insertSync` / `removeSync` with what they *want* shown. The
/// observable `activeLiveActivities` is that request set filtered by the user's settings
/// (Settings ▸ Live Activities), so NotchView's footprint/animation only reacts to activities that
/// will actually render. All writes are change-only (no redundant @Observable mutations).
@Observable
class ActiveLiveActivitiesManager {
    // the `shared` singleton is declared in Support/Ext-A1.swift

    var _activeLiveActivities: Set<LiveActivity> = []

    var _liveActivitiesSettingsCache: LiveActivitiesSettings = LiveActivitiesSettings()

    // Used to manage async monitoring lifecycle
    @ObservationIgnored var task: Task<(), Never>? = nil

    /// what producers asked for, before the settings filter.
    @ObservationIgnored private(set) var requestedActivities: Set<LiveActivity> = []

    /// per-activity enable test (installed by LiveActivitiesStartup from the
    /// Defaults-backed settings). Default: everything allowed.
    @ObservationIgnored var isAllowed: (LiveActivity) -> Bool = { _ in true }

    var activeLiveActivities: Set<LiveActivity> {
        _activeLiveActivities
    }

    init() {
        self._activeLiveActivities = []
        self._liveActivitiesSettingsCache = LiveActivitiesSettings()
    }

    func insertSync(_ activity: LiveActivity) {
        onMain {
            guard !self.requestedActivities.contains(activity) else { return }
            self.requestedActivities.insert(activity)
            self.recompute()
        }
    }

    func removeSync(_ activity: LiveActivity) {
        onMain {
            guard self.requestedActivities.contains(activity) else { return }
            self.requestedActivities.remove(activity)
            self.recompute()
        }
    }

    /// re-applies `isAllowed` (call after the settings change).
    func recompute() {
        let visible = requestedActivities.filter { isAllowed($0) }
        if visible != _activeLiveActivities {
            _activeLiveActivities = visible
        }
    }

    private func onMain(_ body: @escaping () -> Void) {
        if Thread.isMainThread { body() } else { DispatchQueue.main.async(execute: body) }
    }
}
