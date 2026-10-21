// Audio widget (2026-10-20), like Control Center ▸ Sound: the output devices (and, optionally,
// the input devices in a second column) with the current default on a glass pill (as in the Fan
// Control profile list); clicking a row makes it the default. Below the outputs an output volume
// slider with a mute button, below the inputs a level meter of the default input (only while the
// widget is visible and microphone access is granted; otherwise no meter). Apple-style per
// Support/NookWidgetChrome.swift. Data: AudioDevicesManager (CoreAudio).
import SwiftUI
import AppKit
import CoreAudio

enum AudioDevicesWidgetLayout {
    static let rowHeight: CGFloat = 26
    static let oneColumnCells: CGFloat = 4    // 200 pt: outputs only
    static let twoColumnCells: CGFloat = 8    // 400 pt: outputs | inputs

    /// Grid cells (NookWidgetLayout.cells(of: .audioDevices)).
    static func preferredCells() -> CGFloat {
        guard Thread.isMainThread else { return twoColumnCells }
        return MainActor.assumeIsolated { cells(for: SettingsStore[.audioDevicesWidgetSettings]) }
    }

    static func cells(for settings: AudioDevicesWidgetSettings) -> CGFloat {
        settings.showInputs ? twoColumnCells : oneColumnCells
    }
}

/// What the widget shows (the manager's live values, or fixed DEBUG preview values).
struct AudioDevicesSnapshot {
    var outputs: [AudioDevice]
    var inputs: [AudioDevice]
    var defaultOutputID: AudioObjectID
    var defaultInputID: AudioObjectID
    var volume: Float?
    var volumeSettable: Bool
    var isMuted: Bool?
    var inputLevel: Float?
}

struct AudioDevicesWidgetView: View {
    @State private var manager = AudioDevicesManager.shared
    @StoredSetting(.audioDevicesWidgetSettings) private var settings
    /// DEBUG previews: fixed values instead of the manager's (nothing is changed on click).
    var preview: AudioDevicesSnapshot? = nil
    /// DEBUG previews: settings instead of the stored ones.
    var previewSettings: AudioDevicesWidgetSettings? = nil

    private var config: AudioDevicesWidgetSettings { previewSettings ?? settings }

    private var snapshot: AudioDevicesSnapshot {
        if let preview { return preview }
        return AudioDevicesSnapshot(
            outputs: manager.outputs, inputs: manager.inputs,
            defaultOutputID: manager.defaultOutputID, defaultInputID: manager.defaultInputID,
            volume: manager.volume, volumeSettable: manager.volumeSettable, isMuted: manager.isMuted,
            inputLevel: manager.isMeterRunning ? manager.inputLevel : nil)
    }

    private var wantsMeter: Bool { config.showInputs && config.showInputLevel }

    var body: some View {
        let s = snapshot
        HStack(alignment: .top, spacing: NookWidgetMetrics.spacing + 4) {
            column(title: String(localized: "Output"), icon: "speaker.wave.2", devices: s.outputs,
                   selected: s.defaultOutputID, input: false) {
                if preview == nil { AirPodsListeningModeRow(output: s.outputs.first { $0.id == s.defaultOutputID }) } // F7:
                if config.showVolume { volumeRow(s) }
            }
            if config.showInputs {
                column(title: String(localized: "Input"), icon: "mic", devices: s.inputs,
                       selected: s.defaultInputID, input: true) {
                    if config.showInputLevel, let level = s.inputLevel { AudioLevelMeter(level: level) }
                }
            }
        }
        .nookWidgetFrame()
        .onAppear {
            guard preview == nil else { return }
            manager.start()
            if wantsMeter { manager.addMeterClient() }
        }
        .onDisappear {
            guard preview == nil else { return }
            if wantsMeter { manager.removeMeterClient() }
        }
        .onChange(of: wantsMeter) { _, wanted in
            guard preview == nil else { return }
            if wanted { manager.addMeterClient() } else { manager.removeMeterClient() }
        }
    }

    private func column<Footer: View>(title: String, icon: String, devices: [AudioDevice], selected: AudioObjectID,
                                      input: Bool, @ViewBuilder footer: () -> Footer) -> some View {
        VStack(alignment: .leading, spacing: NookWidgetMetrics.stackSpacing) {
            NookWidgetHeaderLabel(title: Text(title), systemImage: icon)
            if devices.isEmpty {
                NookWidgetEmptyState(systemImage: input ? "mic.slash" : "speaker.slash",
                                     title: input ? String(localized: "No input devices") : String(localized: "No output devices"))
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(devices) { device in
                            AudioDeviceRow(device: device, input: input, isSelected: device.id == selected) {
                                guard preview == nil, device.id != selected else { return }
                                manager.setDefault(device, input: input)
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            footer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func volumeRow(_ s: AudioDevicesSnapshot) -> some View {
        let muted = s.isMuted == true
        let value = s.volume ?? 0
        return HStack(spacing: 6) {
            Button {
                guard preview == nil else { return }
                manager.setMuted(!muted)
            } label: {
                Image(systemName: Self.speakerSymbol(volume: value, muted: muted))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(muted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .frame(width: 22, height: 22)
                    .contentShape(Circle())
                    .nookGlass(in: Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .disabled(s.isMuted == nil)
            .help(muted ? String(localized: "Unmute") : String(localized: "Mute"))
            .accessibilityLabel(muted ? Text("Unmute") : Text("Mute"))
            Slider(value: Binding(
                get: { Double(s.volume ?? 0) },
                set: { v in if preview == nil { manager.setVolume(Float(v)) } }
            ), in: 0...1)
            .controlSize(.mini)
            .disabled(!s.volumeSettable)
            .opacity(muted ? 0.5 : 1)
            .accessibilityLabel(Text("Output volume"))
            Text(s.volume == nil ? "–" : "\(Int((value * 100).rounded()))%")
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
                .lineLimit(1)
        }
        .frame(height: 24)
        .help(s.volume == nil ? String(localized: "This device has no volume control") : "")
    }

    static func speakerSymbol(volume: Float, muted: Bool) -> String {
        if muted || volume <= 0 { return "speaker.slash.fill" }
        if volume < 0.34 { return "speaker.wave.1.fill" }
        if volume < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

/// One device: SF Symbol in a circle, name, and — when it is the default — a checkmark, bold
/// white text and the glass pill (Fan Control profile list style).
struct AudioDeviceRow: View {
    let device: AudioDevice
    let input: Bool
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                NookIconBadge(systemImage: device.systemImage(input: input), diameter: 20, symbolSize: 11,
                              isActive: isSelected)
                Text(device.name)
                    .font(.callout)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(NookSelectionTextStyle.style(isSelected: isSelected, colorScheme: colorScheme))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.leading, 3)
            .padding(.trailing, 8)
            .frame(height: AudioDevicesWidgetLayout.rowHeight)
            .nookSelectionPill(isSelected: isSelected, hovering: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(device.name)
        .accessibilityLabel(Text(device.name))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Horizontal level bar (green, amber above −12 dBFS, red above −3 dBFS).
struct AudioLevelMeter: View {
    var level: Float

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "mic.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(LinearGradient(stops: [.init(color: .green, location: 0),
                                                     .init(color: .green, location: 0.75),
                                                     .init(color: .yellow, location: 0.85),
                                                     .init(color: .red, location: 1)],
                                             startPoint: .leading, endPoint: .trailing))
                        .mask(alignment: .leading) {
                            Capsule().frame(width: max(geo.size.width * CGFloat(level), level > 0.01 ? 4 : 0))
                        }
                }
            }
            .frame(height: 6)
            .animation(.linear(duration: 0.08), value: level)
        }
        .frame(height: 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Input level"))
        .accessibilityValue(Text(verbatim: "\(Int((level * 100).rounded()))%"))
    }
}
