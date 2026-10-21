// TimerHaptics — trackpad haptics of the timer creator: a detent per wheel step (`tick`) and a
// double "lock" pulse when a value snaps (`lock`). Gated by Settings ▸ General ▸ Haptic feedback;
// ticks of one wheel are debounced to at most one per 16 ms.
import AppKit

@MainActor
final class TimerHaptics {
    static let shared = TimerHaptics()

    private var lastTick: [TimerWheelUnit: Date] = [:]
    private let tickMinInterval: TimeInterval = 0.016
    private let performer = NSHapticFeedbackManager.defaultPerformer

    private var hapticsEnabled: Bool { SettingsStore[.generalSettings].hapticFeedbackEnabled }

    private init() {}

    /// Two alignment pulses 50 ms apart.
    func lock() {
        guard hapticsEnabled else { return }
        performer.perform(.alignment, performanceTime: .now)
        performAgain(.alignment, after: 0.05)
    }

    /// One detent for a step of `unit` (hours get a double pulse).
    func tick(_ unit: TimerWheelUnit) {
        guard hapticsEnabled, shouldFire(unit) else { return }
        switch unit {
        case .hours:
            // NSHapticFeedbackManager has no "stop" pattern (iOS); a second generic pulse stands in
            performer.perform(.generic, performanceTime: .now)
            performAgain(.generic, after: 0.025)
        case .minutes:
            performer.perform(.levelChange, performanceTime: .now)
        case .seconds:
            performer.perform(.alignment, performanceTime: .now)
        }
    }

    private func shouldFire(_ unit: TimerWheelUnit) -> Bool {
        let now = Date()
        if let last = lastTick[unit], now.timeIntervalSince(last) < tickMinInterval {
            return false
        }
        lastTick[unit] = now
        return true
    }

    private func performAgain(_ pattern: NSHapticFeedbackManager.FeedbackPattern, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                self?.performer.perform(pattern, performanceTime: .now)
            }
        }
    }
}
