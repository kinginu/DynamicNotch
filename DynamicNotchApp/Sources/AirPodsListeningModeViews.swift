// F7 (2026-10-21): AirPods listening mode in the Audio widget (below the output list, when
// AirPods with listening modes are the current output) and its section in Settings ▸ Widgets ▸
// Audio. Model: AirPodsNoiseControlService (AirPodsNoiseControl.swift, docs/airpods.md).
import SwiftUI
import AppKit

/// Audio widget row: a segmented glass control with one segment per offered mode; without
/// Accessibility access a "Sound Settings…" button instead (the fallback).
struct AirPodsListeningModeRow: View {
    let output: AudioDevice?
    @State private var service = AirPodsNoiseControlService.shared
    @StoredSetting(.airPodsListeningModeControl) private var enabled

    var body: some View {
        if enabled, let target = service.target(for: output) {
            content(target)
                .frame(height: 24)
                .onAppear { service.refreshPermission() }
        }
    }

    @ViewBuilder
    private func content(_ target: AirPodsNoiseControlTarget) -> some View {
        HStack(spacing: 6) {
            Image(systemName: target.model.systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)
            if service.accessibilityGranted {
                AirPodsListeningModePicker(
                    modes: service.modes(for: target),
                    selection: service.displayedMode(for: target),
                    busy: service.isBusy(target)
                ) { service.select($0, for: target) }
                .contextMenu {
                    Button("Read Current Mode") { service.refresh(target) }
                        .disabled(service.isBusy(target))
                    Button("Open Sound Settings") { service.openSoundSettings() }
                }
                if let error = service.error(for: target) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.orange)
                        .help(error.message)
                        .accessibilityLabel(Text(verbatim: error.message))
                }
            } else {
                Button {
                    service.openSoundSettings()
                } label: {
                    Text("Open Sound Settings")
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 22)
                        .contentShape(Capsule())
                        .nookGlass(in: Capsule(), interactive: true)
                }
                .buttonStyle(.plain)
                .help("Allow Accessibility access for DynamicNotch in Settings ▸ Widgets ▸ Audio to switch the AirPods listening mode here.")
            }
        }
    }
}

/// Icon segments on a glass capsule; the selected one on an accent pill. Unknown selection (not
/// read yet): no segment highlighted.
struct AirPodsListeningModePicker: View {
    let modes: [AirPodsListeningMode]
    let selection: AirPodsListeningMode?
    var busy: Bool = false
    let action: (AirPodsListeningMode) -> Void

    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(modes, id: \.self) { mode in
                let selected = mode == selection
                Button { action(mode) } label: {
                    Image(systemName: mode.systemImage)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(selected ? AnyShapeStyle(Color.white) : AnyShapeStyle(.secondary))
                        .frame(maxWidth: .infinity)
                        .frame(height: 20)
                        .background {
                            if selected {
                                Capsule().fill(Color.accentColor).matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(mode.title)
                .accessibilityLabel(Text(verbatim: mode.title))
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(1)
        .frame(height: 22)
        .nookGlass(in: Capsule())
        .opacity(busy ? 0.6 : 1)
        .animation(.snappy(duration: 0.2), value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Listening Mode"))
    }
}

/// Settings ▸ Widgets ▸ Audio: the toggle, Accessibility access, and the current AirPods.
struct AirPodsListeningModeSettingsSection: View {
    @State private var service = AirPodsNoiseControlService.shared
    @State private var audio = AudioDevicesManager.shared
    @StoredSetting(.airPodsListeningModeControl) private var enabled

    private var target: AirPodsNoiseControlTarget? {
        service.target(for: audio.outputs.first { $0.id == audio.defaultOutputID })
    }

    var body: some View {
        Section {
            Toggle("Show AirPods listening mode", isOn: $enabled)
            PermissionStatusRow(
                kind: .accessibility,
                granted: "Accessibility access is on.",
                notDetermined: "Switching the listening mode uses the Sound menu in the menu bar, which needs Accessibility access.",
                denied: "Accessibility access is off. Turn on DynamicNotch in System Settings ▸ Privacy & Security ▸ Accessibility to switch the listening mode here.",
                allowTitle: "Allow Accessibility Access")
            if !service.accessibilityGranted {
                Button("Open Sound Settings") { service.openSoundSettings() }
            }
            if let target {
                HStack {
                    Label { Text(verbatim: target.name) } icon: { Image(systemName: target.model.systemImage) }
                    Spacer()
                    Text(verbatim: service.displayedMode(for: target)?.title ?? String(localized: "Unknown"))
                        .foregroundStyle(.secondary)
                    Button("Read Current Mode") { service.refresh(target) }
                        .disabled(!service.accessibilityGranted || service.isBusy(target))
                }
                if let error = service.error(for: target) {
                    Text(verbatim: error.message).font(.caption).foregroundStyle(.orange)
                }
            }
        } header: {
            Text("AirPods Listening Mode")
        } footer: {
            Text("Shown when AirPods Pro, AirPods Max or AirPods 4 with Active Noise Cancellation are the output. Switching opens the Sound menu in the menu bar for a moment and closes it again. The Sound item must be in the menu bar (System Settings ▸ Control Center ▸ Sound).")
                .settingsFootnote()
        }
        .onAppear {
            audio.start()
            service.refreshPermission()
        }
    }
}
