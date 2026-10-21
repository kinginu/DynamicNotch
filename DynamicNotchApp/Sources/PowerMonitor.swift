import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
import Foundation
import IOKit
import IOKit.ps
import Observation
import os


@Observable
final class PowerMonitor: @unchecked Sendable {

    // MARK: - Nested types

    /// Battery state bucket used by makeBucket / evaluateTransition (nil before the first reading).
    enum Bucket: Int, Equatable, Hashable, Sendable {
        case critical  = 0  // unused in current logic, reserved
        case charging  = 1  // isCharging && pct < 100
        case medium    = 2  // !isCharging && pct >= threshold
        case full      = 3  // isCharging && pct >= 100
        case low       = 4  // !isCharging && pct < threshold
    }

    struct BatteryStatus: Equatable, Sendable {
        var pct: Int
        var isCharging: Bool
        var timeToEmpty: Int
        /// 0 = time remaining information IS available, 1 = NOT available
        var noTimeInfo: Bool

        /// - If !isCharging && timeToEmpty >= 1 && !noTimeInfo:
        ///     format timeToEmpty as minutes (<60) or hours (>=60)
        /// - Otherwise: format as "\(pct)%"
        var formattedTimeRemaining: String {
            if !isCharging, timeToEmpty >= 1, !noTimeInfo {
                if timeToEmpty < 60 {
                    return "\(timeToEmpty)m"
                } else {
                    return "\(timeToEmpty / 60)h"
                }
            } else {
                return "\(pct)%"
            }
        }
    }

    // MARK: - Stored properties

    var status: BatteryStatus? = nil

    var isApplicable: Bool = true

    private var runLoopSource: CFRunLoopSource?

    private var timer: Timer?

    private var previousBucket: Bucket? = nil

    // Suppresses transition evaluation during startup until settings load
    private var startupSuppressActive: Bool = true

    private var settingsTask: Task<Void, Never>? = nil

    /// called on the main thread after `status` changes (LiveActivitiesStartup's
    /// battery live activity). Not observation-tracked.
    @ObservationIgnored var onStatusChange: ((BatteryStatus?) -> Void)? = nil

    // MARK: - Init / Deinit

    /// Sets up power-source monitoring, retries once after the run loop has spun, and evaluates the
    /// first transition once the settings are available.
    init() {
        // Calls setupPowerSourceMonitoring() synchronously
        setupPowerSourceMonitoring()

        // Fire-and-forget Task (priority .high) that re-calls setupPowerSourceMonitoring
        // This is a second chance setup after the run loop has spun once.
        Task(priority: .high) { [weak self] in
            self?.setupPowerSourceMonitoring()
        }

        // Stored Task observing BatteryLiveActivitySettings from UserDefaults
        // values streamed from UserDefaults. On first value, if startupSuppressActive is
        // still true, it refreshes and evaluates the transition.
        settingsTask = Task { [weak self] in
            guard let self else { return }
            // Read BatteryLiveActivitySettings from UserDefaults
            // For now, do an initial refresh + transition evaluation if still in startup.
            if self.startupSuppressActive {
                self.refresh()
                // first transition evaluated, then normal operation
                if let st = self.status { self.evaluateTransition(pct: st.pct, isCharging: st.isCharging) }
                self.startupSuppressActive = false
            }
        }
    }

    deinit {
        // Remove runLoopSource from main run loop
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        }

        // Invalidate timer
        timer?.invalidate()

        // Cancel settingsTask
        settingsTask?.cancel()
    }

    // MARK: - Power source monitoring

    /// Uses IOPSNotificationCreateRunLoopSource for IOKit power source change callbacks.
    /// Registers on main run loop in default mode, then trigers an initial refresh.
    private func setupPowerSourceMonitoring() {
        // IOPSNotificationCreateRunLoopSource with a callback
        // that calls refresh() on any power source change
        // C callback + Unmanaged context instead of a capturing closure
        // init and the follow-up Task both call this; register the source once
        guard runLoopSource == nil else { refresh(); return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        let source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<PowerMonitor>.fromOpaque(ctx).takeUnretainedValue().refresh()
        }, context)?.takeRetainedValue()

        guard let source else { return }

        // Add to main run loop in default mode
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)

        // Store reference
        self.runLoopSource = source

        // Trigger initial refresh
        refresh()
    }

    // MARK: - Refresh

    /// Reads IOKit power source information (blop/sources list/power source description),
    /// extracts "Is Charging", "Current Capacity", and "Time to Empty" keys,
    /// builds a BatteryStatus, and conditionally evaluates transition.
    func refresh() {
        // IOPSCopyPowerSourcesInfo()
        // no power source info (desktop Mac / transient failure): clear the status
        guard let blop = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            if status != nil { status = nil; onStatusChange?(nil) }
            return
        }

        // IOPSCopyPowerSourcesList(blob) → NSArray → bridge to Swift
        guard let sourcesList = IOPSCopyPowerSourcesList(blop)?.takeRetainedValue() else {
            if status != nil { status = nil; onStatusChange?(nil) }
            return
        }

        let sources: [Any] = (sourcesList as? [Any]) ?? []

        // First element → IOPSGetPowerSourceDescription → NSDictionary → bridge
        guard !sources.isEmpty,
              let description = IOPSGetPowerSourceDescription(blop, sources[0] as CFTypeRef)?.takeUnretainedValue() as? [String: Any]
        else {
            // No valid power source → mark not applicable, clear status
            if isApplicable {
                isApplicable = false
            }
            if status != nil { status = nil; onStatusChange?(nil) }  // change-only
            return
        }

        // Mark applicable if previously false
        if !isApplicable {
            isApplicable = true
        }

        // Extract "Is Charging" (Bool)
        let isCharging: Bool = (description["Is Charging"] as? Bool) ?? false

        // Extract "Current Capacity" (Int)
        let pct: Int = (description["Current Capacity"] as? Int) ?? 0

        // Extract "Time to Empty" (Int)
        // then a dynamic cast to Int. If the key is absent or the cast fails,
        // timeToEmpty defaults to 0 and the invert flag (noTimeInfo) is set to 1.
        let timeToEmpty: Int
        let noTimeInfo: Bool
        if let rawTime = description["Time to Empty"] as? Int {
            timeToEmpty = rawTime
            noTimeInfo = false
        } else {
            timeToEmpty = 0
            noTimeInfo = true
        }

        // Build BatteryStatus and assign
        let newStatus = BatteryStatus(
            pct: pct,
            isCharging: isCharging,
            timeToEmpty: timeToEmpty,
            noTimeInfo: noTimeInfo
        )

        // change-only write (IOPS notifications fire often with identical values)
        guard newStatus != status else { return }
        status = newStatus
        onStatusChange?(newStatus)

        // Evaluate transition only if startup suppression not active
        if !startupSuppressActive {
            evaluateTransition(pct: pct, isCharging: isCharging)
        }
        // While startupSuppressActive is true, the settingsTask closure
        // handles evaluating the first transition once settings are loaded.
    }

    // MARK: - Bucket calculation

    private func makeBucket(pct: Int, isCharging: Bool, threshold: Int) -> Bucket {
        if pct < 100 {
            // Below full capacity
            if isCharging {
                return .charging
            }
            // Falls through to threshold check below
        } else {
            // At or above 100%
            if isCharging {
                return .full
            }
            // Falls through to threshold check below
        }

        // Not charging: compare against threshold
        if pct < threshold {
            return .low
        }
        return .medium
    }

    // MARK: - Transition evaluation

    /// - Reads batteryLiveActivitySettings threshold from UserDefaults
    /// - Computes new bucket
    /// - If bucket changed to .low, dispatches fireTransient on main queue
    /// - Updates previousBucket
    private func evaluateTransition(pct: Int, isCharging: Bool) {
        // Read threshold from UserDefaults BatteryLiveActivitySettings
        let threshold = batteryLiveActivityThreshold()

        // Compute bucket
        let newBucket = makeBucket(pct: pct, isCharging: isCharging, threshold: threshold)

        // Skip if bucket unchanged
        guard newBucket != previousBucket else {
            return
        }

        // On .low transition, dispatch async fireTransient on main queue
        // and no flags, then calls dispatch_async_f on the main queue.
        if newBucket == .low {
            DispatchQueue.main.async(qos: .unspecified, flags: []) { [weak self] in
                self?.fireTransient()
            }
        }

        // Update previousBucket
        previousBucket = newBucket
    }

    // MARK: - Transient notification

    /// Dispatches an async work item on the main queue that trigers
    /// the low-battery transient visual notification.
    private func fireTransient() {
        // Async dispatch on main queue with .unspecified QoS
        // dispatches it on the main dispatch queue.
        DispatchQueue.main.async(qos: .unspecified, flags: []) {
            // The block body trigers the transient low-battery UI.
            // This posts a notification that the UI layer observes.
            NotificationCenter.default.post(
                name: .init("DynamicNotchBatteryLowTransient"),
                object: nil
            )
        }
    }

    // MARK: - Helpers

    /// Reads the low-battery threshold from BatteryLiveActivitySettings
    ///   Defaults.AnyKey.batteryLiveActivitySettings
    /// and reads its value from UserDefaults.standard.
    private func batteryLiveActivityThreshold() -> Int {
        // BatteryLiveActivitySettings has no threshold field; use the documented fallback.
        return 20
    }
}

// convenience accessors used by other views
extension PowerMonitor {
    var batteryStatus: BatteryStatus? { status }
}

extension PowerMonitor.BatteryStatus {
    var isOnBattery: Bool { !isCharging }
}
