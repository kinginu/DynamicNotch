// TimersManager — named one-shot main-run-loop timers; adding a timer under an existing name
// replaces it. Used by MediaManager for the "dismiss after 15 s paused" timer.
import Foundation

@MainActor
final class TimersManager {
    static let shared = TimersManager()

    private var timers: [String: Timer] = [:]

    private init() {}

    /// Schedules `cb` once after `delay` seconds under `name` (replacing a timer of that name).
    func addTimer(_ name: String, delay: Double, cb: @escaping @MainActor @Sendable () -> Void) {
        timers[name]?.invalidate()
        let timer = Timer(timeInterval: delay, repeats: false) { _ in
            MainActor.assumeIsolated { cb() }
        }
        RunLoop.main.add(timer, forMode: .common)
        timers[name] = timer
    }

    /// Registers an already scheduled `timer` under `name`, invalidating the previous one.
    func replaceMainThreadTimer(_ name: String, timer: Timer) {
        timers[name]?.invalidate()
        timers[name] = timer
    }

    /// Invalidates and forgets the timer named `name`.
    func removeTimer(_ name: String) {
        timers.removeValue(forKey: name)?.invalidate()
    }
}
