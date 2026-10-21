// F4 automation surface (2026-10-20): the app's AutomationActions — thin calls into the
// existing managers (the same calls the widgets make). No new state, no new SMC write path:
// fan profiles go through `FanControlProfiles.apply` (the Fan Control widget's selector).
import Foundation
import AppKit
import SwiftUI
#if canImport(FanControlKit)
import FanControlCore
import FanControlKit
import FanControlUI
#endif

@MainActor
final class LiveAutomationActions: AutomationActions {

    var nookWidgets: [NookWidget] { SettingsStore[.nookSettings].widgets }

    // MARK: Fan Control

    #if canImport(FanControlKit)
    var isFanControlAvailable: Bool { true }
    var isFanControlEnabled: Bool { FanControlSettingKey.general.value.isEnabled }

    func applyFanProfile(_ reference: FanProfileReference) async -> AutomationOutcome {
        let profiles = FanControlProfiles.all
        let id: UUID?
        if case .builtIn(let choice) = reference {
            id = Self.builtInID(choice)
        } else {
            // display names first (a custom slot renamed "Quiet"), then the short aliases
            id = reference.match(in: profiles.map { profile in
                (profile.id, [profile.name, FanControlFormatting.profileName(profile)])
            }) ?? reference.aliasFallback.map(Self.builtInID)
        }
        guard let id, let profile = profiles.first(where: { $0.id == id }) else {
            return .failure(.profileNotFound(reference.description))
        }
        if profile.id == FanProfile.BuiltInID.automatic { return await returnFansToAutomatic() }
        let name = FanControlFormatting.profileName(profile)
        guard await Self.ensureFansDiscovered() else { return .failure(.noFans) }
        if profile.id == FanControlProfiles.activeID, FanControlManager.shared.isSMCWriteSessionOpen {
            return .success("\(name) is already active")
        }
        do {
            try await FanControlProfiles.apply(profile)
            return .success("Applied \(name)")
        } catch {
            return .failure(.failed(error.localizedDescription))
        }
    }

    func returnFansToAutomatic() async -> AutomationOutcome {
        guard await Self.ensureFansDiscovered() else { return .failure(.noFans) }
        do {
            // always runs (no "already active" shortcut): also hands back fans still in manual
            // mode and closes a write session left open
            try await FanControlManager.shared.restoreDefaultControl()
            return .success("Returned fans to automatic")
        } catch {
            return .failure(.failed(error.localizedDescription))
        }
    }

    /// `fans` is filled by the first poll. With "auto-start monitoring" off, or on a cold launch
    /// from a URL / intent, nothing has polled yet: run one poll (`refreshNow()` opens the SMC
    /// for that poll only and does not start monitoring) and wait up to ~2 s for discovery.
    private static func ensureFansDiscovered() async -> Bool {
        let manager = FanControlManager.shared
        if !manager.fans.isEmpty { return true }
        manager.refreshNow()
        for _ in 0..<20 where manager.fans.isEmpty {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return !manager.fans.isEmpty
    }

    private static func builtInID(_ choice: FanProfileChoice) -> UUID {
        switch choice {
        case .automatic: return FanProfile.BuiltInID.automatic
        case .constantQuiet: return FanProfile.BuiltInID.constantQuiet
        case .constantHigh: return FanProfile.BuiltInID.constantHigh
        case .boost: return FanProfile.BuiltInID.boost
        case .max: return FanProfile.BuiltInID.max
        case .custom1: return FanProfile.BuiltInID.custom1
        case .custom2: return FanProfile.BuiltInID.custom2
        }
    }
    #else
    var isFanControlAvailable: Bool { false }
    var isFanControlEnabled: Bool { false }
    func applyFanProfile(_ reference: FanProfileReference) async -> AutomationOutcome { .failure(.fanControlUnavailable) }
    func returnFansToAutomatic() async -> AutomationOutcome { .failure(.fanControlUnavailable) }
    #endif

    // MARK: Timers

    func startTimer(seconds: Int, label: String) {
        NookTimersStore.shared.add(label: label, totalSeconds: seconds)
    }

    func stopTimers(label: String?) -> Int {
        let store = NookTimersStore.shared
        let matching = store.timers.filter { entry in
            guard let label else { return true }
            return entry.label.compare(label, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        for entry in matching { store.cancel(entry) }
        return matching.count
    }

    // MARK: Notch

    func openNotch() {
        withAnimation(.notchOpen) { DynamicNotchState.shared.select(.nook) }
    }

    func closeNotch() {
        withAnimation(.notchClose) {
            for state in DynamicNotchState.perScreen.values where state.mode != .closed { state.mode = .closed }
        }
    }

    func showWidget(_ widget: NookWidget) {
        let pager = NookWidgetPager.shared
        let pages = pager.pages(SettingsStore[.nookSettings])
        if let location = NookPagesModel.location(of: widget, in: pages) {
            // not animated: the notch opens straight onto the page (it sizes itself to that page)
            pager.show(page: location.page, count: pages.count, animated: false)
        }
        openNotch()
    }

    // MARK: Capture

    var isCaptureIdle: Bool { CaptureManager.shared.phase == .idle }
    var allowsAutomationCaptures: Bool { SettingsStore[.automationAllowsCaptures] }

    func capture(_ kind: CaptureKind) {
        // an open notch is closed first so it is not captured (CaptureManager.start)
        let open = DynamicNotchState.perScreen.values.first { $0.mode != .closed }
        CaptureManager.shared.start(kind, notch: open)
    }

    // MARK: Keep Awake

    var isKeepAwakeActive: Bool { KeepAwakeManager.shared.isActive }

    func keepAwakeOn(_ duration: KeepAwakeDuration?) -> Bool {
        let manager = KeepAwakeManager.shared
        manager.activate(duration ?? SettingsStore[.keepAwakeWidgetSettings].lastDuration)
        return manager.isActive
    }

    func keepAwakeOff() {
        KeepAwakeManager.shared.deactivate()
    }

    // MARK: Pomodoro

    var isPomodoroRunning: Bool { PomodoroStore.shared.isRunning }

    func pomodoro(_ action: PomodoroAction) {
        let store = PomodoroStore.shared
        switch action {
        case .start: store.resume()   // starts an idle phase or resumes a paused one
        case .pause: store.pause()
        case .skip: store.skip()
        }
    }
}
