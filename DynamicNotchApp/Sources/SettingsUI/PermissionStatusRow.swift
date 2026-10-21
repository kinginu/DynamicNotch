// One row showing the state of a privacy permission in a settings pane, the same in every pane
// (Audio, Weather, Network, Bluetooth, Batteries, Capture, Menu Bar, Next Up, Calendar, Reminders):
//
//   [status symbol]  message for the current status      [Allow… | Open System Settings | Allowed]
//
// `kind` / `status` are PermissionCenter's types (Support/PermissionCenter.swift); without a
// `status` the row shows PermissionCenter's (observable), and while the row is on screen the center
// keeps the statuses current (`beginMonitoring`), so a switch flipped in System Settings shows up
// without reopening the pane. The button
// follows the status: `.notDetermined` → the allow button (the system prompt), denied / restricted
// / limited → "Open System Settings" (macOS prompts only once), granted / unavailable → none
// ("Allowed" when the row has a title). Without `allow` / `openSettings` the row asks
// PermissionCenter itself; panes whose manager must react to the answer (start a meter, reload
// calendars) pass the manager's own request.
//
// Messages are per status and optional: a status without a message shows only the title (with
// `showsTitle`) or, without a title either, no row at all (e.g. a pane that shows the calendar
// list instead of a "granted" row).
import SwiftUI

struct PermissionStatusRow: View {
    let kind: AppPermission
    private let explicitStatus: PermissionStatus?
    private let showsTitle: Bool
    private let fallbackMessage: LocalizedStringKey?
    private let granted: LocalizedStringKey?
    private let notDetermined: LocalizedStringKey?
    private let denied: LocalizedStringKey?
    private let unavailable: LocalizedStringKey?
    private let allowTitle: LocalizedStringKey
    private let allow: (() -> Void)?
    private let openSettings: (() -> Void)?

    /// - Parameters:
    ///   - status: the status to show (default: `PermissionCenter.shared.status(for: kind)`); a
    ///     pane passes its manager's status when that has a meaning of its own (Weather: no fix).
    ///   - showsTitle: show `kind.title` ("Screen Recording") above the message (the message is then
    ///     a caption), for panes that list several permissions.
    ///   - message: the message for every status without one of its own (below).
    ///   - granted / notDetermined / denied / unavailable: the message for that status (`denied`
    ///     also covers restricted and limited).
    ///   - allowTitle: title of the button shown while `.notDetermined`.
    ///   - allow: asks for the permission (default: `PermissionCenter.requestAccess`).
    ///   - openSettings: opens the Privacy pane (default: `PermissionCenter.openSystemSettings`).
    init(kind: AppPermission, status: PermissionStatus? = nil, showsTitle: Bool = false,
         message: LocalizedStringKey? = nil,
         granted: LocalizedStringKey? = nil, notDetermined: LocalizedStringKey? = nil,
         denied: LocalizedStringKey? = nil, unavailable: LocalizedStringKey? = nil,
         allowTitle: LocalizedStringKey = "Allow…",
         allow: (() -> Void)? = nil, openSettings: (() -> Void)? = nil) {
        self.kind = kind
        self.explicitStatus = status
        self.showsTitle = showsTitle
        self.fallbackMessage = message
        self.granted = granted
        self.notDetermined = notDetermined
        self.denied = denied
        self.unavailable = unavailable
        self.allowTitle = allowTitle
        self.allow = allow
        self.openSettings = openSettings
    }

    private var status: PermissionStatus {
        explicitStatus ?? PermissionCenter.shared.status(for: kind)
    }

    private var message: LocalizedStringKey? {
        let specific: LocalizedStringKey?
        switch status {
        case .granted: specific = granted
        case .notDetermined: specific = notDetermined
        case .denied, .restricted, .limited: specific = denied
        case .unavailable: specific = unavailable
        }
        return specific ?? fallbackMessage
    }

    var body: some View {
        if showsTitle || message != nil {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(symbolStyle)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    if showsTitle {
                        Text(verbatim: kind.title)
                        if let message { Text(message).settingsFootnote() }
                    } else if let message {
                        Text(message).foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                trailing
            }
            .onAppear { PermissionCenter.shared.beginMonitoring() }
            .onDisappear { PermissionCenter.shared.endMonitoring() }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch status {
        case .notDetermined:
            Button(allowTitle) {
                if let allow { allow() } else { PermissionCenter.shared.requestAccess(kind) }
            }
        case .denied, .restricted, .limited:
            Button("Open System Settings") {
                if let openSettings { openSettings() } else { PermissionCenter.shared.openSystemSettings(for: kind) }
            }
        case .granted:
            if showsTitle {
                Text("Allowed").foregroundStyle(.secondary)
            }
        case .unavailable:
            EmptyView()
        }
    }

    private var symbol: String {
        switch status {
        case .granted: return "checkmark.circle.fill"
        case .unavailable: return "minus.circle.fill"
        case .notDetermined, .denied, .restricted, .limited: return "exclamationmark.circle.fill"
        }
    }

    private var symbolStyle: AnyShapeStyle {
        switch status {
        case .granted: return AnyShapeStyle(Color.green)
        case .unavailable: return AnyShapeStyle(.tertiary)
        case .notDetermined, .denied, .restricted, .limited: return AnyShapeStyle(Color.orange)
        }
    }
}
