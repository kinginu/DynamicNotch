// F1 (2026-10-20): "Limit charging to 80 %" — the Apple Silicon SMC charge-hold key CHWA,
// written by the privileged fan control helper through its dedicated request
// (FanControl/docs/helper.md "Charge limit (CHWA)"). Two entry points:
// - `ChargeLimitBadge`: a small "80%" capsule on this Mac's row of the Batteries widget
//   (BatteriesWidgetView.swift, BatteryDeviceRow). Hidden while unknown / unsupported.
// - `ChargeLimitSettingsSection`: Settings ▸ Nook ▸ Widgets ▸ Batteries (BatteriesWidgetSettingsView).
// State comes from `FanControlManager.shared.chargeLimit` (FanControlKit `ChargeLimitController`):
// read unprivileged from the SMC; a change is an explicit user action only, never automatic.
import SwiftUI

#if canImport(FanControlKit)
import FanControlKit

struct ChargeLimitBadge: View {
    @State private var controller = FanControlManager.shared.chargeLimit

    var body: some View {
        Group {
            switch controller.status {
            case .unknown, .unsupported:
                EmptyView()
            default:
                badge
            }
        }
        .task { await controller.refresh(ifOlderThan: 30) }
    }

    private var isOn: Bool { controller.status.isOn }

    private var badge: some View {
        Button {
            let target = !isOn
            Task { try? await controller.setEnabled(target) }
        } label: {
            HStack(spacing: 2) {
                if controller.isBusy {
                    ProgressView().controlSize(.mini)
                } else if isOn {
                    Image(systemName: "checkmark")
                }
                Text(verbatim: "80%")
            }
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .foregroundStyle(foreground)
            .background(Capsule().fill(isOn ? AnyShapeStyle(Color.green.opacity(0.18)) : AnyShapeStyle(.quaternary)))
            .opacity(controller.status == .needsHelper(isOn: isOn) ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(controller.isBusy)
        .help(helpText)
        .accessibilityLabel(Text("Limit charging to 80 %"))
        .accessibilityValue(Text(isOn ? "On" : "Off"))
    }

    private var foreground: AnyShapeStyle {
        if controller.lastError != nil { return AnyShapeStyle(Color.red) }
        return isOn ? AnyShapeStyle(Color.green) : AnyShapeStyle(.secondary)
    }

    private var helpText: Text {
        if let message = controller.errorMessage { return Text(verbatim: message) }
        switch controller.status {
        case .needsHelper:
            return Text("Limit charging to 80 %: the fan control helper is needed to change this.")
        default:
            return isOn ? Text("Limit charging to 80 %: On. Click to charge to 100 %.")
                        : Text("Limit charging to 80 %: Off. Click to stop charging at 80 %.")
        }
    }
}

struct ChargeLimitSettingsSection: View {
    @State private var controller = FanControlManager.shared.chargeLimit

    var body: some View {
        Section {
            Toggle("Limit charging to 80 %", isOn: Binding(
                get: { controller.status.isOn },
                set: { enabled in Task { try? await controller.setEnabled(enabled) } }
            ))
            .disabled(!controller.status.isAvailable || controller.isBusy)
            LabeledContent("Status") {
                HStack(spacing: 6) {
                    if controller.isBusy { ProgressView().controlSize(.small) }
                    statusText
                }
            }
            if case .unsupported(let reason) = controller.status {
                Text(verbatim: reason)
                    .settingsFootnote()
            }
            if let message = controller.errorMessage {
                Text(verbatim: message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Button("Check Again") {
                controller.clearError()
                Task { await controller.refresh() }
            }
            .disabled(controller.isBusy)
        } header: {
            Text("Charging")
        } footer: {
            Text("The setting is kept by the Mac's System Management Controller, not by DynamicNotch: it stays on after DynamicNotch quits and is not undone when fan control stops. An SMC reset or a firmware update may turn it off. Changing it requires the fan control helper.")
                .settingsFootnote()
        }
        .task { await controller.refresh() }
    }

    private var statusText: Text {
        switch controller.status {
        case .unknown:
            return Text("Checking…")
        case .on:
            return Text("On — charging stops at 80 %")
        case .off:
            return Text("Off — charges to 100 %")
        case .unsupported:
            return Text("Not supported on this Mac")
        case .unreadable:
            return Text("Unknown — the current setting could not be read")
        case .needsHelper(let isOn):
            switch isOn {
            case true?: return Text("On — the fan control helper is needed to change it")
            case false?: return Text("Off — the fan control helper is needed to change it")
            case nil: return Text("The fan control helper is needed to change it")
            }
        }
    }
}

#else
// CLT harness without FanControlKit: nothing to show.
struct ChargeLimitBadge: View {
    var body: some View { EmptyView() }
}

struct ChargeLimitSettingsSection: View {
    var body: some View { EmptyView() }
}
#endif
