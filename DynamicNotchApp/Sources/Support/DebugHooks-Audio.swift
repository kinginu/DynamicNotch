// DEBUG-only commands of the Audio widget (2026-10-20), registered with DebugCommandRegistry
// by DebugHooks.install:
//   audiolog            start the manager and log the devices, defaults, volume/mute and the
//                       microphone status ("[Audio] …"). Read-only: nothing is switched or set.
//   audiopreview:<dir>  write <dir>/audio-<live|sample|outputs-only|empty>-<dark|light>.png (the
//                       widget offscreen at its grid width × 202 pt; `sample` = fixed devices with a
//                       level meter, `outputs-only` = one column without volume) and
//                       settings-<dark|light>.png (Settings ▸ Widgets ▸ Audio at 520 pt).
#if DEBUG
import SwiftUI
import AppKit
import CoreAudio

extension DebugHooks {
    @MainActor static func registerAudioCommands() {
        DebugCommandRegistry.register("audiolog", "start the manager, log devices / defaults / volume / mic (read-only)") { _ in
            AudioDevicesManager.shared.start()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { logAudio() }
        }
        DebugCommandRegistry.register("audiopreview", usage: "audiopreview:<dir>", "Audio widget live / sample / outputs-only / empty + settings") { arg in
            AudioDevicesManager.shared.start()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                logAudio()
                WidgetSnapshotter.session(arg, tag: "[Audio]") { audioPreview(to: $0) }
            }
        }
    }

    @MainActor private static func logAudio() {
        let m = AudioDevicesManager.shared
        NSLog("[Audio] defaultOutput=%u defaultInput=%u volume=%@ settable=%d muted=%@ mic=%@ canUseMicrophone=%d",
              m.defaultOutputID, m.defaultInputID, m.volume.map { String(format: "%.3f", $0) } ?? "nil",
              m.volumeSettable, m.isMuted.map { "\($0)" } ?? "nil", "\(m.microphoneStatus)",
              AudioDevicesManager.canUseMicrophone)
        for d in m.devices {
            NSLog("[Audio] %u | %@ | %@ | %@ out=%d in=%d headphones=%d icon(out)=%@ icon(in)=%@",
                  d.id, d.name, d.uid, d.transport.rawValue, d.hasOutput, d.hasInput, d.isHeadphones,
                  d.systemImage(input: false), d.systemImage(input: true))
        }
    }

    static let audioSample: AudioDevicesSnapshot = {
        let devices = [
            AudioDevice(id: 1, uid: "a", name: "MacBook Pro Speakers", transport: .builtIn, hasOutput: true, hasInput: false),
            AudioDevice(id: 2, uid: "b", name: "AirPods Pro", transport: .bluetooth, hasOutput: true, hasInput: true),
            AudioDevice(id: 3, uid: "c", name: "LG UltraFine Display", transport: .displayPort, hasOutput: true, hasInput: false),
            AudioDevice(id: 4, uid: "d", name: "Living Room", transport: .airPlay, hasOutput: true, hasInput: false),
            AudioDevice(id: 5, uid: "e", name: "MacBook Pro Microphone", transport: .builtIn, hasOutput: false, hasInput: true),
            AudioDevice(id: 6, uid: "f", name: "Yeti Stereo Microphone", transport: .usb, hasOutput: false, hasInput: true),
        ]
        return AudioDevicesSnapshot(outputs: devices.filter(\.hasOutput), inputs: devices.filter(\.hasInput),
                                    defaultOutputID: 2, defaultInputID: 5, volume: 0.62, volumeSettable: true,
                                    isMuted: false, inputLevel: 0.58)
    }()

    @MainActor private static func audioPreview(to dir: URL) {
        var outputsOnly = AudioDevicesWidgetSettings()
        outputsOnly.showInputs = false
        outputsOnly.showVolume = false
        let empty = AudioDevicesSnapshot(outputs: [], inputs: [], defaultOutputID: 0, defaultInputID: 0,
                                         volume: nil, volumeSettable: false, isMuted: nil, inputLevel: nil)
        let cases: [(String, AudioDevicesSnapshot?, AudioDevicesWidgetSettings)] = [
            ("live", nil, AudioDevicesWidgetSettings()),
            ("sample", audioSample, AudioDevicesWidgetSettings()),
            ("outputs-only", audioSample, outputsOnly),
            ("empty", empty, AudioDevicesWidgetSettings()),
        ]
        for (name, snapshot, settings) in cases {
            let width = AudioDevicesWidgetLayout.cells(for: settings) * NookWidgetLayout.cell
            WidgetSnapshotter.widget("audio-\(name)", in: dir, width: width) {
                AudioDevicesWidgetView(preview: snapshot ?? liveSnapshot(), previewSettings: settings)
            }
        }
        WidgetSnapshotter.settings("settings", in: dir, size: CGSize(width: 520, height: 720)) { AudioDevicesWidgetSettingsView() }
    }

    /// The live values as a fixed snapshot (so the offscreen render never starts the meter).
    @MainActor private static func liveSnapshot() -> AudioDevicesSnapshot {
        let m = AudioDevicesManager.shared
        return AudioDevicesSnapshot(outputs: m.outputs, inputs: m.inputs, defaultOutputID: m.defaultOutputID,
                                    defaultInputID: m.defaultInputID, volume: m.volume, volumeSettable: m.volumeSettable,
                                    isMuted: m.isMuted, inputLevel: m.isMeterRunning ? m.inputLevel : nil)
    }
}
#endif
