// Feature F3: workload-linked fan profiles (host glue).
// Compiled only when the FanControl package is linked (the Xcode target); the CLT harness
// (Package.swift) does not depend on FanControl, so `canImport(FanControlKit)` is false there.
#if canImport(FanControlKit)
import AppKit
import Observation
import FanControlCore
import FanControlKit
import FanControlUI

/// Drives `WorkloadProfileEngine` (FanControlKit) from the running / frontmost apps
/// (`NSWorkspace` notifications) and a small CPU / GPU sampler (`SystemLoadSampler`), applies
/// the profile it decides, and mirrors its state into `FanControlAutomationState.shared`
/// (FanControlUI: Settings ▸ Fan Control ▸ Automation, the Fan widget's "Auto: …" line).
///
/// Precedence is owned by F2's `FanProfileArbiter` (manual > emergency > workload > power >
/// default; FanControl/docs/kit.md "Profile precedence and automation"). This coordinator only
/// claims / withdraws the arbiter's `.workload` layer and never applies a profile itself:
/// - **Manual** picks are the arbiter's classification (`manualSelectionNotification`); they
///   pause the engine for `manualOverrideMinutes`. During the pause the claim is withdrawn
///   **without** ending the arbiter's manual override (`endsManualOverride: false`), so a stale
///   workload profile can neither come back through the Power status line's "Resume" nor hide
///   power-rule transitions. When the engine re-engages afterwards (a rule still matches) it
///   claims again and the arbiter's override is ended too (`resumeAutomation()`).
/// - **Power** profiles claim `.power` themselves and win whenever no workload claim is set.
/// - **Errors** shown in the Automation tab (`state.lastApplyError`) mirror the arbiter's live
///   state by observation: its `lastError` while the decision in effect is the workload claim
///   and that decision failed (`failedDecision`). A failed workload claim is retried at most
///   every `retryInterval` while its rule keeps matching.
///
/// Settings: `FanControlSettingKey.automation`. Nothing runs while automation or fan control
/// itself (the master switch) is off.
@MainActor
final class WorkloadProfileCoordinator {

    static let shared = WorkloadProfileCoordinator()

    /// Load sampling / rule evaluation period while automation is on.
    static let tickInterval: TimeInterval = 2
    /// Minimum time between retries of a failed workload claim.
    static let retryInterval: TimeInterval = 60
    /// The only place automation affects the active profile: sets (`claim` non-nil) or withdraws
    /// (`nil`) the arbiter's `.workload` claim. `endManualOverride` also ends the arbiter's
    /// manual override (re-engaging after a pause); `preserveManualOverride` withdraws / changes
    /// the claim without ending it (during a pause). Errors are not reported here: the arbiter
    /// may coalesce the apply into a later pass, so they are mirrored by observation instead.
    var applyWorkloadProfile: @MainActor (_ claim: ProfileClaim?, _ endManualOverride: Bool, _ preserveManualOverride: Bool) async -> Void = { claim, endManualOverride, preserveManualOverride in
        let arbiter = FanProfileArbiter.shared
        await arbiter.setClaim(claim, for: .workload, endsManualOverride: !preserveManualOverride)
        if endManualOverride, arbiter.arbitration.isManualOverrideActive {
            await arbiter.resumeAutomation()
        }
    }

    private var settings: WorkloadAutomationSettings
    private var engine: WorkloadProfileEngine
    private let sampler = SystemLoadSampler()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var settingsTask: Task<Void, Never>?
    private var isStarted = false
    /// The `.workload` claim last sent to the arbiter (`nil` = none).
    private var currentClaim: ProfileClaim?
    /// Claim updates run one after another, in order.
    private var claimTask: Task<Void, Never>?
    /// When a failed workload claim was last retried.
    private var lastRetry: Date?

    private var manager: FanControlManager { FanControlManager.shared }
    private var state: FanControlAutomationState { FanControlAutomationState.shared }

    init() {
        settings = FanControlSettingKey.automation.value
        engine = WorkloadProfileEngine(settings: settings)
    }

    // MARK: Lifecycle

    /// Called once at launch (FanControlStartup, after the manager exists).
    func start() {
        guard !isStarted else { return }
        isStarted = true
        FanProfileArbiter.shared.startObservingHost()   // idempotent (power profiles start it too)
        state.onResume = { [weak self] in self?.resumeAutomation() }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluate(at: Date()) }
            })
        }
        // The arbiter classifies manual picks (a change it did not make); automatic switches by
        // either layer are not manual.
        observers.append(NotificationCenter.default.addObserver(
            forName: FanProfileArbiter.manualSelectionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let id = note.userInfo?["profileID"] as? UUID
            MainActor.assumeIsolated { self?.manualSelection(id) }
        })
        settingsTask = Task { @MainActor [weak self] in
            for await settings in FanControlSettingKey.automation.updates(initial: false) {
                self?.settingsDidChange(settings)
            }
        }
        observeArbiterErrors()
        syncTimer()
        evaluate(at: Date())
    }

    /// Ends a manual-override pause now.
    func resumeAutomation() {
        engine.resume()
        evaluate(at: Date())
    }

    private func manualSelection(_ id: UUID?) {
        engine.noteManualSelection(id, at: Date())
        evaluate(at: Date())
    }

    // MARK: Evaluation

    private func settingsDidChange(_ new: WorkloadAutomationSettings) {
        guard new != settings else { return }
        settings = new
        engine.settings = new
        syncTimer()
        evaluate(at: Date())
    }

    private func syncTimer() {
        let wanted = isStarted && settings.isEnabled
        if wanted, timer == nil {
            _ = sampler.sample()   // prime the CPU tick baseline
            let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            timer.tolerance = 0.5
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else if !wanted, let timer {
            timer.invalidate()
            self.timer = nil
            state.cpuLoad = nil
            state.gpuLoad = nil
        }
    }

    private func tick() {
        let sample = sampler.sample()
        if let cpu = sample.cpu { state.cpuLoad = cpu }
        state.gpuLoad = sample.gpu
        evaluate(at: Date())
    }

    private func evaluate(at now: Date) {
        guard isStarted else { return }
        guard FanControlSettingKey.general.value.isEnabled else {
            // Fan control is off: forget everything, apply nothing.
            engine.reset()
            setStatus(.disabled)
            sendClaim(nil)
            return
        }
        let activeID = manager.profileStore.activeProfileID
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let snapshot = WorkloadSnapshot(runningBundleIDs: running,
                                        frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                                        cpuLoad: state.cpuLoad, gpuLoad: state.gpuLoad,
                                        activeProfileID: activeID,
                                        emergencyActive: manager.emergencyOverrideActive,
                                        availableProfileIDs: Set(FanControlProfiles.all.map(\.id)))
        let wasPaused: Bool
        if case .pausedByManualSelection = state.status { wasPaused = true } else { wasPaused = false }
        let decision = engine.update(snapshot, at: now)
        setStatus(decision.status)
        switch decision.status {
        case .engaged(let id, let reason):
            guard FanControlAutomationProfiles.profile(id) != nil else { return }
            let claim = ProfileClaim(profileID: id, reason: Self.reasonText(reason))
            sendClaim(claim, endManualOverride: wasPaused)
            retryIfFailed(claim, at: now)
        case .idle, .disabled:
            // The engine names its baseline once; the arbiter picks the next layer instead.
            sendClaim(nil)
        case .pausedByManualSelection:
            // The rule behind the claim may stop matching while paused (the engine does not
            // re-evaluate it then): withdraw the claim, keeping the user's manual override.
            sendClaim(nil, preserveManualOverride: true)
        case .heldForEmergency:
            break   // keep the claim as it is
        }
    }

    /// Retries the arbiter's apply of `claim` if it failed (at most every `retryInterval`).
    private func retryIfFailed(_ claim: ProfileClaim, at now: Date) {
        let arbiter = FanProfileArbiter.shared
        guard let decision = arbiter.decision, decision.layer == .workload,
              decision.profileID == claim.profileID, arbiter.failedDecision == decision,
              !arbiter.isApplying else { return }
        if let lastRetry, now.timeIntervalSince(lastRetry) < Self.retryInterval { return }
        lastRetry = now
        let previous = claimTask
        claimTask = Task { @MainActor in
            await previous?.value
            await FanProfileArbiter.shared.retry()
        }
    }

    /// Mirrors the arbiter's error for the workload decision into the Automation tab.
    private func observeArbiterErrors() {
        let arbiter = FanProfileArbiter.shared
        let message = withObservationTracking { () -> String? in
            guard let decision = arbiter.decision, decision.layer == .workload,
                  arbiter.failedDecision == decision else { return nil }
            return arbiter.lastError
        } onChange: {
            Task { @MainActor [weak self] in self?.observeArbiterErrors() }
        }
        if state.lastApplyError != message { state.lastApplyError = message }
    }

    private static func reasonText(_ reason: WorkloadReason) -> String {
        switch reason {
        case .app(_, let name): return "Workload: \(name)"
        case .load(let metric):
            switch metric {
            case .cpu: return "Workload: sustained CPU load"
            case .gpu: return "Workload: sustained GPU load"
            case .either: return "Workload: sustained CPU / GPU load"
            }
        }
    }

    private func setStatus(_ status: WorkloadStatus) {
        if state.status != status { state.status = status }
    }

    private func sendClaim(_ claim: ProfileClaim?, endManualOverride: Bool = false,
                           preserveManualOverride: Bool = false) {
        guard claim != currentClaim || endManualOverride else { return }
        if claim != currentClaim { lastRetry = nil }
        currentClaim = claim
        let previous = claimTask
        claimTask = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            await self.applyWorkloadProfile(claim, endManualOverride, preserveManualOverride)
        }
    }
}
#endif
