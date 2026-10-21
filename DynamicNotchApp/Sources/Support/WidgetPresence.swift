// Shared lifecycle of the Nook widgets' data managers (2026-10-20, refactor R11).
//
// A manager owns one `WidgetPresence` and hands it two closures: `onNeeded` (install its timers /
// observers / sampling) and `onIdle` (tear them down). The presence decides when:
//
//   needed  = a view of the widget is visible (`setVisible`, counted: widget + settings pane +
//             several displays) OR — when a `widget` is given — the widget is in the Nook
//             (`SettingsStore[.nookSettings].widgets`) OR a `touch(holdFor:)` hold is running.
//   active  = `onNeeded` ran and `onIdle` has not run since. It follows `needed`; going idle can
//             be delayed by `idleGrace` (System keeps its history through a quick remove / re-add).
//
// The Nook layout is observed by ONE shared `SettingsStore.updates(.nookSettings)` stream for all
// presences, from the first `activate()` / `setVisible` / `touch` on: removing the widget from the
// Nook tears the manager down right away (not at its next timer tick) and adding it back restarts
// it. `onWake(after:)` registers a "refresh after wake" action: one NSWorkspace observer, installed
// only while active, that runs the action after the delay if the presence is still active.
//
// DEBUG: `debugCheckTick()` (call it from the gated timer's handler) and `debugIsRunning` (checked
// right after `onIdle`) log "[WidgetPresence] <label>: … alive while not needed". Both are no-ops
// in release builds.
import AppKit
import Foundation

@MainActor
final class WidgetPresence {
    /// For logs.
    let label: String
    /// The Nook widget whose presence in the layout keeps the manager running (nil = views only).
    let widget: NookWidget?
    /// Delay between "no longer needed" and `onIdle` (0 = immediately).
    let idleGrace: TimeInterval

    private let onNeeded: @MainActor () -> Void
    private let onIdle: @MainActor () -> Void

    /// Called after every change of the Nook layout (after the needed / idle decision), while
    /// observing. For managers that also react to other parts of the layout.
    var onLayoutChange: (@MainActor () -> Void)?

    private(set) var visibleCount = 0
    /// `onNeeded` ran and `onIdle` has not run since.
    private(set) var isActive = false
    /// The shared Nook layout stream reaches this presence.
    private(set) var isObserving = false

    private var holdUntil: Date?
    private var idleTask: Task<Void, Never>?
    private var wakeActions: [(delay: TimeInterval, action: @MainActor () -> Void)] = []
    private var wakeObserver: NSObjectProtocol?
    /// Bumped on every idle → active transition, so a delayed wake action of an earlier active
    /// period does not run in a later one.
    private var activation = 0

    init(_ widget: NookWidget?, label: String, idleGrace: TimeInterval = 0,
         onNeeded: @escaping @MainActor () -> Void, onIdle: @escaping @MainActor () -> Void) {
        self.widget = widget
        self.label = label
        self.idleGrace = max(0, idleGrace)
        self.onNeeded = onNeeded
        self.onIdle = onIdle
    }

    // MARK: State

    var isVisible: Bool { visibleCount > 0 }

    /// The widget is in the Nook layout (always false without a `widget`).
    var isInNook: Bool {
        guard let widget else { return false }
        return SettingsStore[.nookSettings].widgets.contains(widget)
    }

    /// A `touch(holdFor:)` hold has not expired yet.
    private var isHeld: Bool {
        guard let holdUntil else { return false }
        return holdUntil > Date()
    }

    var isNeeded: Bool { isVisible || isInNook || isHeld }

    // MARK: Inputs

    /// A view of the widget appeared (true) or disappeared (false). Balanced calls; the count
    /// never goes below 0.
    func setVisible(_ visible: Bool) {
        visibleCount = max(0, visibleCount + (visible ? 1 : -1))
        activate()
    }

    /// Starts observing the Nook layout (idempotent) and applies the current state.
    func activate() {
        if !isObserving {
            isObserving = true
            Self.register(self)
        }
        reevaluate()
    }

    /// Runs the manager now even when nothing needs it, for at least `holdFor` seconds (default:
    /// `idleGrace`); for callers that start a manager without a balancing "disappeared" (DEBUG
    /// hooks, views that only call `start()`).
    func touch(holdFor: TimeInterval? = nil) {
        let hold = max(0, holdFor ?? idleGrace)
        let until = Date().addingTimeInterval(hold)
        if holdUntil.map({ $0 < until }) ?? true { holdUntil = until }
        activate()
    }

    /// Tears down now (`onIdle`), whatever needs it; the next input (visibility / layout change /
    /// touch) applies the state again. Drops a pending hold.
    func forceIdle() {
        holdUntil = nil
        goIdle()
    }

    /// Applies needed / idle: runs `onNeeded` or (after the grace / hold) `onIdle` on a transition.
    func reevaluate() {
        if isVisible || isInNook {
            cancelIdle()
            goActive()
        } else if isHeld, let holdUntil {
            goActive()
            scheduleIdle(at: max(holdUntil, Date().addingTimeInterval(idleGrace)))
        } else if isActive {
            if idleGrace > 0 {
                if idleTask == nil { scheduleIdle(at: Date().addingTimeInterval(idleGrace)) }
            } else {
                goIdle()
            }
        }
    }

    /// Registers an action run `delay` seconds after the Mac wakes, while active (also when it
    /// became active during the delay's first part: the action checks `isActive` when it fires).
    func onWake(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        wakeActions.append((delay, action))
        if isActive { installWakeObserver() }
    }

    // MARK: Transitions

    private func goActive() {
        guard !isActive else { return }
        isActive = true
        activation += 1
        #if DEBUG
        debugReported = false
        #endif
        installWakeObserver()
        onNeeded()
    }

    private func goIdle() {
        cancelIdle()
        guard isActive else { return }
        isActive = false
        holdUntil = nil
        removeWakeObserver()
        onIdle()
        #if DEBUG
        if let probe = debugIsRunning {
            // checked on the next turn, after the manager's own follow-up work
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, !self.isActive, probe() else { return }
                    self.debugReport("still running after onIdle")
                }
            }
        }
        #endif
    }

    private func scheduleIdle(at date: Date) {
        idleTask?.cancel()
        let delay = max(0, date.timeIntervalSinceNow)
        idleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.idleTask = nil
            if self.isNeeded { self.reevaluate() } else { self.goIdle() }
        }
    }

    private func cancelIdle() {
        idleTask?.cancel()
        idleTask = nil
    }

    // MARK: Wake

    private func installWakeObserver() {
        guard wakeObserver == nil, !wakeActions.isEmpty else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.didWake() }
        }
    }

    private func removeWakeObserver() {
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
    }

    private func didWake() {
        guard isActive else { return }
        let period = activation
        for (delay, action) in wakeActions {
            Task { @MainActor [weak self] in
                if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                guard let self, self.isActive, self.activation == period else { return }
                action()
            }
        }
    }

    // MARK: Shared Nook layout stream

    private final class WeakRef {
        weak var value: WidgetPresence?
        init(_ value: WidgetPresence) { self.value = value }
    }

    private static var observers: [WeakRef] = []
    private static var layoutTask: Task<Void, Never>?

    private static func register(_ presence: WidgetPresence) {
        observers.removeAll { $0.value == nil }
        observers.append(WeakRef(presence))
        guard layoutTask == nil else { return }
        layoutTask = Task { @MainActor in
            for await _ in SettingsStore.updates(.nookSettings, initial: false) {
                WidgetPresence.layoutChanged()
            }
        }
    }

    private static func layoutChanged() {
        for presence in observers.compactMap(\.value) {
            presence.reevaluate()
            presence.onLayoutChange?()
        }
    }

    // MARK: DEBUG checks

    #if DEBUG
    /// Reports whether the gated work (timer / sampling task) still exists; checked after `onIdle`.
    var debugIsRunning: (@MainActor () -> Bool)?
    private var debugReported = false

    /// Call from the gated timer's handler: logs (once per idle period) when it fires while the
    /// presence is idle, or active past its grace without anything needing it.
    func debugCheckTick(_ what: String = "timer") {
        if !isActive {
            debugReport("\(what) alive while not needed (idle)")
        } else if !isNeeded, idleTask == nil {
            debugReport("\(what) alive while not needed (no idle scheduled)")
        }
    }

    private func debugReport(_ message: String) {
        guard !debugReported else { return }
        debugReported = true
        NSLog("[WidgetPresence] %@: %@ (visible=%ld inNook=%d active=%d)",
              label, message, visibleCount, isInNook, isActive)
    }
    #else
    @inline(__always) func debugCheckTick(_ what: String = "timer") {}
    #endif
}
