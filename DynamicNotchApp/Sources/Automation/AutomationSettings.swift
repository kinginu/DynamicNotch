// F4 automation surface (2026-10-21): the user's opt-in for screenshots triggered from
// outside the app. A `dynamicnotch://capture/…` URL can be opened by any local process (or a web
// page after the browser's prompt), so URL captures are refused unless this is on
// (CommandRouter, `.capturesNotAllowed`). App Intents are not gated by it: they run from the
// user's own Shortcuts and can ask for confirmation themselves. docs/automation.md.
import SwiftUI

extension StoredKeys {
    /// Settings ▸ Nook ▸ Widgets ▸ Capture ▸ "Allow automation to take screenshots".
    static let automationAllowsCaptures = Key<Bool>("automationAllowsCaptures", default: false)
}

/// The Capture widget settings' "Automation" section (CaptureWidgetSettingsView).
struct AutomationCaptureSettingsSection: View {
    @StoredSetting(.automationAllowsCaptures) private var allowed

    var body: some View {
        Section {
            Toggle("Allow automation to take screenshots", isOn: $allowed)
        } header: {
            Text("Automation")
        } footer: {
            Text("Lets dynamicnotch://capture URLs and dnctl take screenshots. Any app on this Mac can open these URLs, so leave this off unless you use them.")
                .settingsFootnote()
        }
    }
}
