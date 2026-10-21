// F4 automation surface (2026-10-20): executes an AutomationCommand. The single entry point
// for the URL scheme (URLCommandRouter), the App Intents and therefore `dnctl`.
//
// The policy (which commands need which widget in the Nook, Fan Control on/off) lives here; the
// side effects go through `AutomationActions` so the routing is unit-testable with a fake
// (Tests/AutomationTests). LiveAutomationActions calls the existing managers only — in particular
// fan commands use the same path as the Fan Control widget (`FanControlProfiles.apply`), no new
// SMC write path.
import Foundation

/// Where a command came from. URLs (the scheme and `dnctl`) can be opened by any local process,
/// or by a web page once the browser's prompt is accepted; App Intents run from the user's own
/// Shortcuts / Spotlight / Siri and can ask for confirmation (`requestConfirmation`) themselves.
enum AutomationSource: Equatable, Sendable {
    case url
    case intent
}

/// Side effects of the automation commands (LiveAutomationActions in the app, a fake in tests).
@MainActor
protocol AutomationActions: AnyObject {
    /// The widgets currently in the Nook (SettingsStore[.nookSettings].widgets).
    var nookWidgets: [NookWidget] { get }

    /// FanControlKit is linked (false in the SwiftPM harness).
    var isFanControlAvailable: Bool { get }
    /// Settings ▸ Fan Control ▸ "Enable Fan Control".
    var isFanControlEnabled: Bool { get }
    /// Applies a fan profile through the Fan Control widget's path; returns the profile's name.
    func applyFanProfile(_ reference: FanProfileReference) async -> AutomationOutcome
    /// Hands every fan back to the SMC (`FanControlManager.restoreDefaultControl()`, the same call
    /// as Settings ▸ Fan Control ▸ "Return to Automatic"). Always runs, even when Automatic is
    /// already the selected profile.
    func returnFansToAutomatic() async -> AutomationOutcome

    func startTimer(seconds: Int, label: String)
    /// Cancels the matching timers (all when `label` is nil); returns how many.
    func stopTimers(label: String?) -> Int

    func openNotch()
    func closeNotch()
    /// Switches the Nook's pager to the page holding `widget`, then opens the notch.
    func showWidget(_ widget: NookWidget)

    /// False while a capture / recording is already in progress.
    var isCaptureIdle: Bool { get }
    /// Settings ▸ Nook ▸ Widgets ▸ Capture ▸ "Allow automation to take screenshots" (default off).
    var allowsAutomationCaptures: Bool { get }
    func capture(_ kind: CaptureKind)

    var isKeepAwakeActive: Bool { get }
    /// Starts a session; false when IOKit refused the power assertion.
    func keepAwakeOn(_ duration: KeepAwakeDuration?) -> Bool
    func keepAwakeOff()

    var isPomodoroRunning: Bool { get }
    func pomodoro(_ action: PomodoroAction)
}

@MainActor
final class CommandRouter {
    /// The app's router (LiveAutomationActions).
    static let shared = CommandRouter(actions: LiveAutomationActions())

    let actions: AutomationActions

    init(actions: AutomationActions) {
        self.actions = actions
    }

    /// Parses and performs a URL (`dynamicnotch://…`), with the rules for `.url` commands.
    func perform(url: URL) async -> AutomationOutcome {
        switch AutomationCommand.parse(url) {
        case .success(let command): return await perform(command, source: .url)
        case .failure(let error): return .failure(error)
        }
    }

    /// Performs `command`; `.success` carries a short human-readable summary.
    func perform(_ command: AutomationCommand, source: AutomationSource) async -> AutomationOutcome {
        switch command {
        case .fanProfile(let reference):
            if let error = fanPrecondition() { return .failure(error) }
            return await actions.applyFanProfile(reference)

        case .fanAutomatic:
            if let error = fanPrecondition() { return .failure(error) }
            return await actions.returnFansToAutomatic()

        case .timerStart(let seconds, let label):
            actions.startTimer(seconds: seconds, label: label)
            let name = label.isEmpty ? "Timer" : label
            return .success("Started \(name) (\(Self.duration(seconds)))")

        case .timerStop(let label):
            let count = actions.stopTimers(label: label)
            if count == 0 {
                return label.map { .failure(.failed("No timer named “\($0)”.")) } ?? .success("No timers running")
            }
            return .success(count == 1 ? "Stopped 1 timer" : "Stopped \(count) timers")

        case .notchOpen:
            actions.openNotch()
            return .success("Opened the notch")

        case .notchClose:
            actions.closeNotch()
            return .success("Closed the notch")

        case .widgetShow(let widget):
            guard actions.nookWidgets.contains(widget) else { return .failure(.widgetNotInNook(widget.name)) }
            actions.showWidget(widget)
            return .success("Showing \(widget.name)")

        case .capture(let kind):
            // A URL can come from any process: without the user's opt-in it must not take a
            // screenshot under DynamicNotch's Screen Recording grant (and, with the Clipboard
            // destination, hand it to whoever reads the pasteboard next).
            if source == .url, !actions.allowsAutomationCaptures { return .failure(.capturesNotAllowed) }
            guard actions.isCaptureIdle else { return .failure(.busy("Capture")) }
            actions.capture(kind)
            return .success("Capturing \(kind.rawValue)")

        case .keepAwake(let action):
            // the session only lives while its widget is in the Nook (KeepAwakeManager ends it otherwise)
            guard actions.nookWidgets.contains(.keepAwake) else { return .failure(.widgetNotInNook(NookWidget.keepAwake.name)) }
            let turnOn: Bool
            var duration: KeepAwakeDuration? = nil
            switch action {
            case .on(let d):
                // already on and no duration given: keep the running session (do not restart it)
                if actions.isKeepAwakeActive && d == nil { return .success("Keep Awake is on") }
                turnOn = true
                duration = d
            case .off: turnOn = false
            case .toggle: turnOn = !actions.isKeepAwakeActive
            }
            if turnOn {
                guard actions.keepAwakeOn(duration) else { return .failure(.failed("Keep Awake could not create a power assertion.")) }
                return .success("Keep Awake on")
            }
            actions.keepAwakeOff()
            return .success("Keep Awake off")

        case .pomodoro(let action):
            // the widget holds the only Stop / Reset controls (PomodoroStore resets when it leaves the Nook)
            guard actions.nookWidgets.contains(.pomodoro) else { return .failure(.widgetNotInNook(NookWidget.pomodoro.name)) }
            if action == .start, actions.isPomodoroRunning { return .success("Focus session already running") }
            if action == .pause, !actions.isPomodoroRunning { return .success("Focus session is not running") }
            actions.pomodoro(action)
            switch action {
            case .start: return .success("Focus session started")
            case .pause: return .success("Focus session paused")
            case .skip: return .success("Skipped to the next phase")
            }
        }
    }

    private func fanPrecondition() -> AutomationError? {
        guard actions.isFanControlAvailable else { return .fanControlUnavailable }
        guard actions.isFanControlEnabled else { return .fanControlDisabled }
        return nil
    }

    /// "25 min", "1 h 30 min", "45 s".
    static func duration(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h) h") }
        if m > 0 { parts.append("\(m) min") }
        if s > 0 || parts.isEmpty { parts.append("\(s) s") }
        return parts.joined(separator: " ")
    }
}
