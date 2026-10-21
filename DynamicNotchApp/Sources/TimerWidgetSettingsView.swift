// Settings ▸ Nook ▸ Widgets ▸ Timer: the five preset chips (duration + optional
// label, "Restore Defaults"), Recents in the "…" menu, seconds, the closed-notch display, and the
// iOS Clock "When Timer Ends" sound with the alert duration (TimerWidgetSettings).
import SwiftUI

struct TimerWidgetSettingsView: View {
    @StoredSetting(.timerWidgetSettings) private var settings

    var body: some View {
        TimerWidgetSettingsForm(settings: $settings)
    }
}

/// The form itself (a binding, so the debug snapshots can render sample settings).
struct TimerWidgetSettingsForm: View {
    @Binding var settings: TimerWidgetSettings

    var body: some View {
        SettingsForm {
            Section {
                ForEach(0..<TimerPreset.slotCount, id: \.self) { index in
                    TimerPresetRow(index: index, preset: presetBinding(index))
                }
                Toggle("Show Recents in the … menu", isOn: $settings.showRecents)
            } header: {
                SettingsSectionHeader("Presets") {
                    Button("Restore Defaults") { settings.presets = TimerPreset.defaults }
                        .disabled(TimerPreset.normalized(settings.presets) == TimerPreset.defaults)
                }
            } footer: {
                Text("The presets are the chips in the Timer widget; clicking one sets the timer (and its label, if it has one). A preset set to 0 is hidden.")
                    .settingsFootnote()
            }
            Section {
                Toggle("Show seconds", isOn: $settings.showSeconds)
                Toggle("Show running timers in the closed notch", isOn: $settings.showInClosedNotch)
            }
            Section {
                Picker("When Timer Ends", selection: $settings.soundName) {
                    ForEach(TimerWidgetSettings.systemSounds, id: \.self) { name in
                        Text(verbatim: name).tag(name)
                    }
                    Divider()
                    Text("Stop Playing").tag(TimerWidgetSettings.stopPlayingSound)
                    Text("None").tag("")
                }
                .onChange(of: settings.soundName) { _, name in
                    if !name.isEmpty, name != TimerWidgetSettings.stopPlayingSound { NSSound(named: name)?.play() }
                }
                Picker("Alert Duration", selection: $settings.alertSeconds) {
                    Text("10 seconds").tag(10)
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("5 minutes").tag(300)
                    Text("Until Stopped").tag(0)
                }
            } footer: {
                Text("Timers keep running while the notch is closed. When one ends, the notch shows it with Stop and the sound repeats until you stop it in the Timer widget or the alert duration passes. Stop Playing pauses the music instead.")
                    .settingsFootnote()
            }
        }
    }

    private func presetBinding(_ index: Int) -> Binding<TimerPreset> {
        Binding(
            get: { TimerPreset.normalized(settings.presets)[index] },
            set: { value in
                var list = TimerPreset.normalized(settings.presets)
                list[index] = value
                settings.presets = list
            }
        )
    }
}

/// One preset slot: hours / minutes / seconds pickers and an optional label.
struct TimerPresetRow: View {
    let index: Int
    @Binding var preset: TimerPreset

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: "\(index + 1)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .trailing)
            TextField("Label", text: $preset.label, prompt: Text("Label"))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 90)
            unitPicker(Text("Hours"), value: preset.hours, range: 0...23, suffix: "h") { set(h: $0) }
            unitPicker(Text("Minutes"), value: preset.minutes, range: 0...59, suffix: "m") { set(m: $0) }
            unitPicker(Text("Seconds"), value: preset.secondsPart, range: 0...59, suffix: "s") { set(s: $0) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Preset \(index + 1)"))
    }

    private func unitPicker(_ name: Text, value: Int, range: ClosedRange<Int>, suffix: String,
                            set: @escaping (Int) -> Void) -> some View {
        Picker(selection: Binding(get: { value }, set: set)) {
            ForEach(Array(range), id: \.self) { v in
                Text(verbatim: "\(v)\(suffix)").tag(v)
            }
        } label: {
            name
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
        .frame(width: 64, alignment: .trailing)   // equal columns whatever the value's width
        .accessibilityLabel(name)
    }

    private func set(h: Int? = nil, m: Int? = nil, s: Int? = nil) {
        preset.seconds = (h ?? preset.hours) * 3600 + (m ?? preset.minutes) * 60 + (s ?? preset.secondsPart)
    }
}

#if DEBUG
/// DebugHooks (`DebugHooks.notificationName`); command `timerpresets:<dir>` writes
/// `<dir>/timerpresets-settings-<dark|light>.png` (the settings form with sample presets) and
/// `<dir>/timerpresets-creator-<defaults|custom|norecents>-<dark|light>.png` (the widget's creator
/// with those settings), and logs the chips / menu of each case. Ephemeral stores and bindings —
/// nothing is written to the defaults. Installed when a timer creator first appears.
@MainActor
enum TimerPresetsGalleryDebug {
    private static var observer: NSObjectProtocol?

    static func install() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: DebugHooks.notificationName, object: nil, queue: .main
        ) { note in
            guard let command = note.object as? String, command.hasPrefix("timerpresets:") else { return }
            let dir = String(command.dropFirst("timerpresets:".count))
            MainActor.assumeIsolated { render(to: URL(fileURLWithPath: dir)) }
        }
        NSLog("[TimerPresets] installed")
    }

    static var sample: TimerWidgetSettings {
        var s = TimerWidgetSettings()
        s.presets = [
            TimerPreset(seconds: 90, label: "Eggs"),
            TimerPreset(seconds: 240, label: "Tea"),
            TimerPreset(seconds: 0),
            TimerPreset(seconds: 1500, label: "Focus"),
            TimerPreset(seconds: 5400),
        ]
        return s
    }

    static func render(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let previousGlass = NookGlass.forceFallback
        NookGlass.forceFallback = true
        defer { NookGlass.forceFallback = previousGlass }

        // decoding checks: an old value without presets, a longer old list, a short one
        let decoder = JSONDecoder()
        for json in [#"{"soundName":"Glass"}"#,
                     #"{"presets":[{"seconds":60},{"seconds":120},{"seconds":180},{"seconds":240},{"seconds":300},{"seconds":360},{"seconds":420}]}"#,
                     #"{"presets":[{"seconds":30,"label":"Short"}],"showRecents":false}"#,
                     #"{"presets":"garbage","alertSeconds":10}"#] {
            if let v = try? decoder.decode(TimerWidgetSettings.self, from: Data(json.utf8)) {
                NSLog("[TimerPresets] decode %@ -> %@ showRecents=%d alert=%ld", json,
                      v.presets.map { "\($0.seconds)\($0.label.isEmpty ? "" : ":" + $0.label)" }.joined(separator: ","),
                      v.showRecents ? 1 : 0, v.alertSeconds)
            } else {
                NSLog("[TimerPresets] decode %@ FAILED", json)
            }
        }

        var noRecents = sample
        noRecents.showRecents = false
        let cases: [(String, TimerWidgetSettings)] = [("defaults", TimerWidgetSettings()), ("custom", sample), ("norecents", noRecents)]
        let width = NookWidgetLayout.width(of: .timer)
        for (name, settings) in cases {
            let store = NookTimersStore(persistent: false)
            store.debugSeed([], alerting: false)
            NSLog("[TimerPresets] %@ chips=%@ menuRecents=%ld", name,
                  TimerCreatorView.chipPresets(settings).map { TimerRowView.shortDuration($0.seconds) }.joined(separator: " "),
                  settings.showRecents ? store.recents.count : 0)
            for dark in [true, false] {
                let view = TimerCreatorView(onStart: { _, _ in }, store: store, settingsOverride: settings)
                    .frame(width: width, height: WidgetGalleryDebug.rowHeight)
                    .padding(12)
                    .background(dark ? Color.black : Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, dark ? .dark : .light)
                write(view, dark: dark, size: CGSize(width: width + 24, height: WidgetGalleryDebug.rowHeight + 24),
                      to: dir.appendingPathComponent("timerpresets-creator-\(name)-\(dark ? "dark" : "light").png"))
            }
        }
        for dark in [true, false] {
            let view = TimerWidgetSettingsForm(settings: .constant(sample))
                .frame(width: 520, height: 760)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, dark ? .dark : .light)
            write(view, dark: dark, size: CGSize(width: 520, height: 760),
                  to: dir.appendingPathComponent("timerpresets-settings-\(dark ? "dark" : "light").png"))
        }
    }

    private static func write<V: View>(_ view: V, dark: Bool, size: CGSize, to url: URL) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        host.layoutSubtreeIfNeeded()
        host.display()
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: url)
                NSLog("[TimerPresets] wrote %@", url.path)
            }
        }
        window.orderOut(nil)
    }
}
#endif
