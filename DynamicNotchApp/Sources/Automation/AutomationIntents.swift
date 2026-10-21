// F4 automation surface (2026-10-20): App Intents for Shortcuts / Spotlight / Siri.
// Every intent builds an AutomationCommand and runs it through CommandRouter.shared, so the
// intents, the URL scheme and `dnctl` share one code path and one set of rules.
//
// Discovery note: Shortcuts reads the App Shortcuts metadata that Xcode extracts at build time
// (Metadata.appintents); a locally built, ad-hoc signed app may need to be launched once (and
// sometimes be in /Applications) before Shortcuts lists them.
import AppIntents
import Foundation

// MARK: - Parameter types

extension FanProfileChoice: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Fan Profile"
    static let caseDisplayRepresentations: [FanProfileChoice: DisplayRepresentation] = [
        .automatic: "Automatic",
        .constantQuiet: "Constant Quiet",
        .constantHigh: "Constant High",
        .boost: "Boost",
        .max: "Max",
        .custom1: "Custom 1",
        .custom2: "Custom 2",
    ]
}

enum KeepAwakeIntentMode: String, AppEnum {
    case toggle, on, off

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Keep Awake Mode"
    static let caseDisplayRepresentations: [KeepAwakeIntentMode: DisplayRepresentation] = [
        .toggle: "Toggle",
        .on: "On",
        .off: "Off",
    ]

    var action: KeepAwakeAction {
        switch self {
        case .toggle: return .toggle
        case .on: return .on(nil)
        case .off: return .off
        }
    }
}

/// AutomationError as an intent error (Shortcuts shows the message).
struct AutomationIntentError: Error, CustomLocalizedStringResourceConvertible {
    let message: String
    var localizedStringResource: LocalizedStringResource { "\(message)" }
}

@MainActor
private func runAutomation(_ command: AutomationCommand) async throws -> some IntentResult & ProvidesDialog {
    // `.intent`: the user's own Shortcut / Spotlight / Siri. An intent that captures the screen
    // must ask first (`requestConfirmation`) — the router does not apply the URL opt-in to intents.
    switch await CommandRouter.shared.perform(command, source: .intent) {
    case .success(let message):
        return .result(dialog: "\(message)")
    case .failure(let error):
        throw AutomationIntentError(message: error.localizedDescription)
    }
}

// MARK: - Intents

struct SetFanProfileIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Fan Profile"
    static let description = IntentDescription("Applies one of the Fan Control profiles. Fan Control must be turned on in Settings.")

    @Parameter(title: "Profile", default: .automatic)
    var profile: FanProfileChoice

    static var parameterSummary: some ParameterSummary {
        Summary("Set fan profile to \(\.$profile)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await runAutomation(.fanProfile(.builtIn(profile)))
    }
}

struct ReturnFansToAutomaticIntent: AppIntent {
    static let title: LocalizedStringResource = "Return Fans to Automatic"
    static let description = IntentDescription("Hands every fan back to the system's automatic control.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await runAutomation(.fanAutomatic)
    }
}

struct StartTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Timer"
    static let description = IntentDescription("Starts a countdown timer in the notch.")

    @Parameter(title: "Minutes", default: 5, inclusiveRange: (1, 1439))
    var minutes: Int

    @Parameter(title: "Label")
    var label: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Start a \(\.$minutes) minute timer") {
            \.$label
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = (label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return try await runAutomation(.timerStart(seconds: minutes * 60, label: String(text.prefix(AutomationCommand.maxLabelLength))))
    }
}

struct ToggleKeepAwakeIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Keep Awake"
    static let description = IntentDescription("Keeps the Mac awake, or lets it sleep again. The Keep Awake widget must be in the Nook.")

    @Parameter(title: "Mode", default: .toggle)
    var mode: KeepAwakeIntentMode

    static var parameterSummary: some ParameterSummary {
        Summary("Keep Awake: \(\.$mode)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await runAutomation(.keepAwake(mode.action))
    }
}

struct StartFocusSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Focus Session"
    static let description = IntentDescription("Starts (or resumes) the Focus / Pomodoro timer. The Focus widget must be in the Nook.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await runAutomation(.pomodoro(.start))
    }
}

// MARK: - App Shortcuts

struct DynamicNotchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SetFanProfileIntent(),
            phrases: [
                "Set fan profile in \(.applicationName)",
                "Set \(.applicationName) fan profile to \(\.$profile)",
            ],
            shortTitle: "Set Fan Profile",
            systemImageName: "fan"
        )
        AppShortcut(
            intent: ReturnFansToAutomaticIntent(),
            phrases: ["Return fans to automatic in \(.applicationName)"],
            shortTitle: "Fans to Automatic",
            systemImageName: "fan.badge.automatic"
        )
        AppShortcut(
            intent: StartTimerIntent(),
            phrases: ["Start a timer in \(.applicationName)"],
            shortTitle: "Start Timer",
            systemImageName: "timer"
        )
        AppShortcut(
            intent: ToggleKeepAwakeIntent(),
            phrases: ["Toggle Keep Awake in \(.applicationName)"],
            shortTitle: "Keep Awake",
            systemImageName: "cup.and.saucer"
        )
        AppShortcut(
            intent: StartFocusSessionIntent(),
            phrases: ["Start a focus session in \(.applicationName)"],
            shortTitle: "Start Focus Session",
            systemImageName: "brain.head.profile"
        )
    }
}
