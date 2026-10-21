import SwiftUI

/// Requests `.battery` for a few seconds when charging starts, and for as long as the battery is
/// low and unplugged (Settings ▸ Live Activities ▸ Battery).
@MainActor @Observable
final class BatteryActivityMonitor {
    nonisolated static let lowBatteryThreshold = 20
    nonisolated static let chargingTransientSeconds: Double = 5

    /// Battery monitor (nil until `start(center:)`).
    private(set) var power: PowerMonitor? = nil

    @ObservationIgnored private weak var center: LiveActivityCenter?
    @ObservationIgnored private var lastCharging: Bool? = nil
    @ObservationIgnored private var transient: DispatchWorkItem? = nil

    private var manager: ActiveLiveActivitiesManager { .shared }

    func start(center: LiveActivityCenter) {
        self.center = center
        let monitor = PowerMonitor()
        monitor.onStatusChange = { [weak self] status in
            DispatchQueue.main.async { self?.handle(status, initial: false) }
        }
        power = monitor
        handle(monitor.status, initial: true)
    }

    /// Re-applies the battery settings to the current status.
    func settingsChanged() {
        handle(power?.status, initial: true)
    }

    private func handle(_ status: PowerMonitor.BatteryStatus?, initial: Bool) {
        guard let status, let settings = center?.batterySettings else {
            lastCharging = nil
            manager.removeSync(.battery)
            return
        }
        let startedCharging = status.isCharging && lastCharging == false
        lastCharging = status.isCharging

        let low = !status.isCharging && status.pct <= Self.lowBatteryThreshold && settings.lowPowerAlert
        if low {
            transient?.cancel()
            transient = nil
            manager.insertSync(.battery)
            return
        }
        let hideBecauseFull = settings.autoHideWhenFull && status.pct >= 100
        if startedCharging, !initial, settings.showChargingStatus, !hideBecauseFull {
            manager.insertSync(.battery)
            transient?.cancel()
            let item = DispatchWorkItem { [weak self] in
                self?.transient = nil
                self?.manager.removeSync(.battery)
            }
            transient = item
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.chargingTransientSeconds, execute: item)
        } else if transient == nil {
            manager.removeSync(.battery)
        }
    }
}

/// One side of the battery activity: battery icon | percentage (or time remaining).
struct BatteryLiveActivityView: View {
    var side: LiveActivityView.ActivitySide
    var power: PowerMonitor?

    var body: some View {
        switch side {
        case .leading:
            if let status = power?.status {
                BatteryIconView(level: CGFloat(status.pct) / 100, isCharging: status.isCharging)
            } else {
                LiveActivityIconView(activity: .battery)
            }
        case .trailing:
            if let status = power?.status {
                let showPct = SettingsStore[.batteryLiveActivitySettings].showPercentage || status.isCharging
                Text(verbatim: showPct ? "\(status.pct)%" : status.formattedTimeRemaining)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(status.isCharging ? Color.green
                                     : (status.pct <= BatteryActivityMonitor.lowBatteryThreshold ? Color.red : .nonShockingWhite))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}
