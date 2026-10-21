// Debug-only remote control for verifying the app without Screen Recording or
// Accessibility permission (neither is granted to the shell the app is tested from, so
// `screencapture` and UI scripting are unavailable). Compiled only in DEBUG builds.
//
// Every command goes through `DebugCommandRegistry` (Support/DebugHooks-Registry.swift): one
// distributed-notification listener on "com.example.dynamicnotch.debug[.<DN_DEBUG_CHANNEL>]" whose
// `object` is the command string "<verb>[:<arg>]", plus the `-DNDebugCommand <cmd>` launch argument
// and the `-DNDebugCommandFile <path>` command file for runs where notifications do not arrive.
// `Tools/dn-debug.sh` sends them; `help` lists every registered command. Snapshot commands
// (`*preview:<dir>`, `widgetgallery:<dir>`) render through `WidgetSnapshotter`
// (Support/DebugHooks-Snapshot.swift) and accept `<dir>?appearance=…&glass=…&settle=…`.
//
// Commands registered here (the widgets' are in Support/DebugHooks-*.swift,
// BluetoothWidgetDebug.swift and WidgetGallery-Debug.swift):
//   snapshot:<dir>      write <dir>/<n>-<title>.png for every visible window (in-process
//                       cacheDisplay rendering; materials/blur may render flatter than on screen)
//   settings:<paneId>   open the settings window at that pane (e.g. general, nook, fanControl)
//   open | open:tray | close   open/close one notch (the screen under the pointer, else the main
//                       screen; notch states are per screen). `open:all` / `open:tray,all` /
//                       `close` (closes every screen) act on all screens.
//   hovertest | menutest:<x>,<y>   hover-out / menu-keeps-open checks on the open notch (see below)
//   notchstate          log every screen's notch mode and window frame
//   animperf:<n>        open/close the notch n times and log the frame timing (AnimPerfProbe)
//   intro:off           persist intro = false (takes effect for RootView on next launch)
//   defaults:<key>=<json>      write a stored setting as its JSON string representation
//   click:<title>:<x>,<y>      synthesize a left click in the window with that title, at (x, y) in
//                       points from the top-left of the window's frame (= snapshot coordinates
//                       divided by the snapshot's scale). In-process NSEvent, no Accessibility needed.
//   fanhelpercheck      same as Settings ▸ Fan Control ▸ General ▸ Check Again
//                       (`FanControlManager.retryHelperConnection()`: reset a helper rejection,
//                       re-read the install status, probe with the read-only `version()` call);
//                       logs helperStatus / helperConnectionState. Never writes the SMC.
//   fanhelperstate      log helperStatus / helperConnectionState only (no I/O)
//   fanpreview:<dir>    write <dir>/widget-<size>-<profile>.png: the Fan Control widget rendered
//                       offscreen (black background, dark appearance) for each of the six fixed
//                       profiles at 2x1 and double-wide, with live fan/sensor data. Uses the
//                       widget's preview-only override (`previewProfile`), so nothing is
//                       applied and no setting or profile selection changes. Also writes
//                       profiles-tab-{boost,max,custom-1,custom-2}.png (Settings ▸ Profiles tab at the
//                       pane's fixed size, via `initialSelection`), and the Temperature widget:
//                       temperature-live-<window>.png (live history, 1 and 5 min) and
//                       temperature-sample-<window>.png (a synthetic 30 min history incl. a gap
//                       and a spike above the alert threshold; preview-only, nothing recorded).
//                       Glass stays as DN_DEBUG_NOGLASS sets it unless `?glass=` says otherwise.
#if DEBUG
import AppKit
import QuartzCore
import SwiftUI
#if canImport(FanControlKit)
import FanControlCore
import FanControlKit
#endif

enum DebugHooks {
    /// "com.example.dynamicnotch.debug", or "com.example.dynamicnotch.debug.<channel>" when the
    /// process was started with the environment variable DN_DEBUG_CHANNEL=<channel>. A second
    /// (development) instance launched with its own channel does not react to commands meant for
    /// the user's running instance, and vice versa.
    static let notificationName: Notification.Name = {
        let base = "com.example.dynamicnotch.debug"
        if let channel = ProcessInfo.processInfo.environment["DN_DEBUG_CHANNEL"], !channel.isEmpty {
            return Notification.Name(base + "." + channel)
        }
        return Notification.Name(base)
    }()

    /// DN_DEBUG_OFFSCREEN=1: notch panels are placed 20 000 pt to the left of their screen so a
    /// development instance never covers (or steals hover from) the user's running instance.
    /// In-process snapshots (`snapshot:`) still render them.
    static let offscreenPanels = ProcessInfo.processInfo.environment["DN_DEBUG_OFFSCREEN"] == "1"
        && ProcessInfo.processInfo.environment["DN_DEBUG_GHOST"] != "1"

    /// DN_DEBUG_GHOST=1 (measurement runs): notch windows stay on screen (so AppKit/SwiftUI keep
    /// rendering and animating them) but at 2 % opacity and ignoring the mouse, so they neither
    /// show nor take hover/clicks from the user's instance.
    static let ghostPanels = ProcessInfo.processInfo.environment["DN_DEBUG_GHOST"] == "1"

    /// NotchView body evaluations (counted only in DEBUG; read by `animperf`).
    static var notchBodyCount = 0
    private static var installed = false

    /// Called once from AppDelegate at launch: registers every debug command, installs the one
    /// listener and runs the `-DNDebugCommand` launch arguments / `-DNDebugCommandFile`.
    static func install() {
        MainActor.assumeIsolated {
            guard !installed else { return }
            installed = true
            DebugCommandRegistry.registerBuiltins()
            registerCoreCommands()
            registerWidgetCommands()
        }
        DebugCommandRegistry.installListener()
        MainActor.assumeIsolated { DebugCommandRegistry.runLaunchArguments() }
    }

    /// Runs one command string (kept for callers of the old entry point).
    @MainActor static func handle(_ command: String) {
        DebugCommandRegistry.dispatch(command)
    }

    /// Every per-widget debug file's registrations. Their `install()` / `install…Hook()` functions
    /// (still called from the widgets' onAppear / managers) only re-register, which is idempotent.
    @MainActor private static func registerWidgetCommands() {
        registerCommandsA()
        registerCommandsB()
        registerCommandsC()
        registerAudioCommands()
        registerBatteriesCommands()
        registerCaptureCommands()
        registerUsageCommands()
        installWorldClockHook()
        BluetoothWidgetDebug.install()
        CalculatorDebug.install()
        ColorPickerDebug.install()
        DownloadsWidgetDebug.install() // F8
        DisplaysWidgetDebug.install()
        KeepAwakeDebugHooks.install()
        MenuBarItemsDebug.install()
        NetworkWidgetDebug.install()
        NextUpDebug.install()
        StorageWidgetDebug.install()
        SystemStatsDebug.install()
        WeatherDebug.install()
        NookWidgetPagesDebug.install() // F9: pages / drag-to-reorder commands
        WidgetGalleryDebug.install()
    }

    @MainActor private static func registerCoreCommands() {
        let r = DebugCommandRegistry.self
        r.register("snapshot", usage: "snapshot:<dir>", "PNG of every visible window (cacheDisplay)") { arg in
            snapshot(to: URL(fileURLWithPath: arg))
        }
        r.register("settings", usage: "settings[:<paneId>]", "open the settings window (general, nook, fanControl, …)") { arg in
            WindowsManager.shared.showSettings(pane: arg.isEmpty ? nil : AppSettings.PaneIdentifier(arg))
        }
        r.register("open", usage: "open[:tray][,all]", "open the notch under the pointer (all = every screen)") { arg in
            let opts = Set(arg.split(separator: ",").map(String.init))
            let targets = opts.contains("all") ? Array(DynamicNotchState.perScreen.values) : [DynamicNotchState.shared]
            withAnimation { for t in targets { t.select(opts.contains("tray") ? .tray : .nook) } }
        }
        r.register("close", "close the notch on every screen") { _ in
            withAnimation { for t in DynamicNotchState.perScreen.values { t.mode = .closed } }
        }
        r.register("intro", usage: "intro:off", "finish the welcome card on every notch (same as clicking it)") { arg in
            SettingsStore[.intro] = (arg != "off")
            for kit in WindowsManager.shared.displayKits.values { kit.dynamicnotchWindow?.contentView?.needsDisplay = true }
        }
        r.register("click", usage: "click:<title>:<x>,<y>", "synthesize a left click in a window (points from its top-left)") { arg in
            click(arg)
        }
        r.register("hovertest", "simulate hover-out on the open notch and log whether it closes") { _ in
            notchHoverTest(menuAt: nil)
        }
        r.register("menutest", usage: "menutest:<x>,<y>", "click (x, y) in the open notch (a menu), then hover out") { arg in
            notchHoverTest(menuAt: arg)
        }
        r.register("notchstate", "log every screen's notch mode and window frame") { _ in
            for (id, kit) in WindowsManager.shared.displayKits {
                NSLog("[DebugHooks] screen %u mode=%@ window=%@", id, kit.notchState.mode.rawValue,
                      NSStringFromRect(kit.dynamicnotchWindow?.frame ?? .zero))
            }
        }
        r.register("animperf", usage: "animperf[:<n>]", "open/close n times (default 5) and log frame timing") { arg in
            AnimPerfProbe.shared.run(cycles: Int(arg) ?? 5)
        }
        r.register("defaults", usage: "defaults:<key>=<json>", "write a stored setting (its JSON string representation)") { arg in
            guard let eq = arg.firstIndex(of: "=") else { return }
            UserDefaults.standard.set(String(arg[arg.index(after: eq)...]), forKey: String(arg[..<eq]))
        }
        #if canImport(FanControlKit)
        r.register("fanhelpercheck", "retry the helper connection (read-only version() probe), log its state") { _ in
            Task { @MainActor in
                let manager = FanControlManager.shared
                do { try await manager.retryHelperConnection() } catch { NSLog("[DebugHooks] fanhelpercheck: %@", "\(error)") }
                logHelperState()
            }
        }
        r.register("fanhelperstate", "log helperStatus / helperConnectionState (no I/O)") { _ in
            logHelperState()
        }
        r.register("fanpreview", usage: "fanpreview:<dir>", "Fan Control widget × profiles × sizes, Profiles tab, Temperature widget") { arg in
            WidgetSnapshotter.session(arg, tag: "[DebugHooks]", glass: .inherit) { fanPreview(to: $0) }
        }
        #endif
    }

    /// `animperf:<n>`: open and close the notch n times on every screen and log the main-thread
    /// frame timing seen by a display link (CADisplayLink of the main screen) during each 0.9 s
    /// transition: frames, mean/p95/max interval and hitches (> 1.5 × the refresh interval), and how
    /// many times NotchView.body ran per transition. A late display-link callback = a main thread
    /// that was busy (layout, body evaluation, AppKit view updates) when the frame was due.
    @MainActor final class AnimPerfProbe: NSObject {
        static let shared = AnimPerfProbe()
        private var link: CADisplayLink?
        private var stamps: [CFTimeInterval] = []
        /// Visible notch-shape geometry per path() call during a transition: (width, height, top y of
        /// the drawn shape within its rect). Recorded by NotchShape.path(in:) (DEBUG).
        static var shapeSamples: [(w: CGFloat, h: CGFloat, top: CGFloat, t: CFTimeInterval)] = []
        static var recording = false
        nonisolated static func recordShape(_ r: CGRect) {
            MainActor.assumeIsolated {
                guard recording, r.width < 2000 else { return }
                shapeSamples.append((r.width, r.height, r.minY, CACurrentMediaTime()))
            }
        }
        private var refresh: CFTimeInterval = 1.0 / 60

        func run(cycles: Int) {
            guard let screen = NSScreen.main else { return }
            let l = screen.displayLink(target: self, selector: #selector(tick(_:)))
            l.add(to: .main, forMode: .common)
            link = l
            Task { @MainActor in
                var results: [String] = []
                for i in 0..<cycles {
                    for (label, open) in [("open", true), ("close", false)] {
                        stamps.removeAll()
                        Self.shapeSamples.removeAll(); Self.recording = true
                        let bodies0 = DebugHooks.notchBodyCount
                        if open { DynamicNotchState.shared.select(.nook) } else { DynamicNotchState.shared.mode = .closed }
                        try? await Task.sleep(nanoseconds: 900_000_000)
                        Self.recording = false
                        results.append(shapeSummary() + " | " + summary("\(label)#\(i + 1)", bodies: DebugHooks.notchBodyCount - bodies0))
                        try? await Task.sleep(nanoseconds: 300_000_000)
                    }
                }
                link?.invalidate(); link = nil
                for r in results { NSLog("[animperf] %@", r) }
            }
        }

        @objc private func tick(_ l: CADisplayLink) {
            refresh = l.targetTimestamp - l.timestamp > 0 ? l.targetTimestamp - l.timestamp : refresh
            stamps.append(CACurrentMediaTime())
        }

        /// Largest frame-to-frame jump of the drawn shape's height and top edge, the drawn height range.
        private func shapeSummary() -> String {
            let s = Self.shapeSamples
            guard s.count > 1 else { return "shape: \(s.count) samples" }
            let dh = zip(s.dropFirst(), s).map { abs($0.h - $1.h) }.max() ?? 0
            let dy = zip(s.dropFirst(), s).map { abs($0.top - $1.top) }.max() ?? 0
            let dt = zip(s.dropFirst(), s).map { ($0.t - $1.t) * 1000 }
            let span = (s.last!.t - s.first!.t) * 1000
            let trace = s.map { String(format: "%.0f", $0.h) }.joined(separator: ",")
            return String(format: "shape: n=%d over %.0fms (max gap %.1fms) h %.0f→%.0f maxΔh/sample=%.1f maxΔtop/sample=%.1f [%@]",
                          s.count, span, dt.max() ?? 0, s.first!.h, s.last!.h, dh, dy, trace)
        }

        private func summary(_ label: String, bodies: Int) -> String {
            let d = zip(stamps.dropFirst(), stamps).map { ($0 - $1) * 1000 }.sorted()
            guard !d.isEmpty else { return "\(label): no frames" }
            let mean = d.reduce(0, +) / Double(d.count)
            let p95 = d[min(d.count - 1, Int(Double(d.count) * 0.95))]
            let hitches = d.filter { $0 > refresh * 1000 * 1.5 }.count
            return String(format: "%@: frames=%d refresh=%.1fms mean=%.2fms p95=%.2fms max=%.2fms hitches=%d bodyEvals=%d",
                          label, d.count + 1, refresh * 1000, mean, p95, d.last!, hitches, bodies)
        }
    }

    /// `hovertest`: on the open notch, simulate the pointer leaving (hover-out) and log whether the
    /// guarded close closes it (expected: closed ≈ 0.35 s later, the pointer being elsewhere).
    /// `menutest:<x>,<y>`: same, but first click (x, y) in the open notch window (top-left points) —
    /// e.g. the Fan Control profile menu — so an NSMenu is tracking: logs the mode while the menu is
    /// open (expected: still open), dismisses the menu after 1.5 s and logs again (expected: closed).
    @MainActor static func notchHoverTest(menuAt arg: String?) {
        guard let kit = WindowsManager.shared.displayKits.values.first(where: { $0.notchState.mode != .closed }),
              let window = kit.dynamicnotchWindow,
              let vm = NotchViewModel.debugByWindow.object(forKey: window) else {
            NSLog("[DebugHooks] hovertest: no open notch"); return
        }
        let state = kit.notchState
        let t0 = ProcessInfo.processInfo.systemUptime
        func log(_ what: String) {
            NSLog("[DebugHooks] hovertest +%.2fs %@: mode=%@ hovering=%d menuDepth=%d busy=%d", ProcessInfo.processInfo.systemUptime - t0,
                  what, state.mode.rawValue, vm.hovering ? 1 : 0, NotchInteractionMonitor.menuTrackingDepth, vm.notchIsBusy ? 1 : 0)
        }
        func after(_ s: TimeInterval, _ block: @escaping () -> Void) {
            let t = Timer(timeInterval: s, repeats: false) { _ in MainActor.assumeIsolated { block() } }
            RunLoop.main.add(t, forMode: .common)
        }
        vm.hovering = true
        vm.setPointerOver(notch: false, band: nil) // → hovering false → applyHover(false) → guard
        if let arg {
            let xy = arg.split(separator: ",").compactMap { Double($0) }
            guard xy.count == 2 else { return }
            after(1.5) { log("menu open"); NotchInteractionMonitor.trackingMenu?.cancelTracking() }
            after(2.5) { log("menu dismissed +1s") }
            after(0.1) {
                let point = NSPoint(x: xy[0], y: window.frame.height - xy[1])
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    if let e = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                  windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                        NSApp.sendEvent(e)
                    }
                }
                log("click returned")
            }
        } else {
            after(0.2) { log("0.2s") }
            after(0.6) { log("0.6s") }
        }
    }

    @MainActor static func click(_ arg: String) {
        let parts = arg.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let window = NSApp.windows.first(where: { $0.isVisible && $0.title == parts[0] }) else {
            NSLog("[DebugHooks] click: no visible window titled %@", arg)
            return
        }
        let xy = parts[1].split(separator: ",").compactMap { Double($0) }
        guard xy.count == 2 else { return }
        // frame-relative top-left → window base coordinates (bottom-left)
        let point = NSPoint(x: xy[0], y: window.frame.height - xy[1])
        window.makeKeyAndOrderFront(nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                              timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: window.windowNumber, context: nil,
                                              eventNumber: 0, clickCount: 1, pressure: 1) {
                NSApp.sendEvent(event)
            }
        }
        NSLog("[DebugHooks] clicked %@ at %@", window.title, NSStringFromPoint(point))
    }

    #if canImport(FanControlKit)
    @MainActor static func logHelperState() {
        let manager = FanControlManager.shared
        NSLog("[DebugHooks] helperStatus=%@ helperConnectionState=%@",
              String(describing: manager.helperStatus), String(describing: manager.helperConnectionState))
    }

    /// Offscreen renders of `FanControlWidgetView` for every fixed profile and both sizes
    /// (`fanpreview:<dir>`, inside a `WidgetSnapshotter.session`). Dark only unless the argument asks
    /// for `appearance=light|both` (light files get a "-light" suffix).
    @MainActor static func fanPreview(to dir: URL) {
        let sizes: [(FanControlWidgetSettings.GridSizeChoice, String)] = [(.medium, "2x1"), (.doubleWide, "doublewide")]
        let appearances = WidgetSnapshotter.appearances(default: [true])
        for profile in FanControlProfiles.all {
            for (size, sizeName) in sizes {
                for dark in appearances {
                    let cell = CGSize(width: size.widthInPoints + 24, height: 226)
                    let view = FanControlWidgetView(previewProfile: profile, previewGridSize: size)
                        .padding(12)
                        .frame(width: cell.width, height: cell.height, alignment: .topLeading)
                        .background(dark ? Color.black : Color(nsColor: .windowBackgroundColor))
                        .environment(\.colorScheme, dark ? .dark : .light)
                    let slug = String(profile.name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" })
                    WidgetSnapshotter.write(view, size: cell, dark: dark,
                                            to: dir.appendingPathComponent("widget-\(sizeName)-\(slug)\(dark ? "" : "-light").png"), settle: 0)
                }
            }
        }
        // Settings ▸ Profiles tab with Boost / Custom 1 / Custom 2 selected (initialSelection only).
        let size = FanControlSettingsView.contentSize
        for (id, slug) in [(FanProfile.BuiltInID.boost, "boost"), (FanProfile.BuiltInID.max, "max"),
                           (FanProfile.BuiltInID.custom1, "custom-1"), (FanProfile.BuiltInID.custom2, "custom-2")] {
            let view = FanControlProfilesTabView(actionError: .constant(nil), initialSelection: id)
                .frame(width: size.width, height: size.height)
                .background(Color(nsColor: .windowBackgroundColor))
            WidgetSnapshotter.write(view, size: size, dark: nil, to: dir.appendingPathComponent("profiles-tab-\(slug).png"))
        }
        // Custom 1 with the whole editor visible (point rows, validation) at a taller height.
        let tall = CGSize(width: size.width, height: 1150)
        WidgetSnapshotter.write(FanControlProfilesTabView(actionError: .constant(nil), initialSelection: FanProfile.BuiltInID.custom1)
                                    .frame(width: tall.width, height: tall.height)
                                    .background(Color(nsColor: .windowBackgroundColor)),
                                size: tall, dark: nil, to: dir.appendingPathComponent("profiles-tab-custom-1-tall.png"))
        // Temperature widget: live history and a synthetic one.
        let cell = CGSize(width: FanControlTemperatureWidgetSettings.widthInPoints + 24, height: 226)
        func temperatureCell<V: View>(_ view: V, dark: Bool) -> some View {
            view.padding(12)
                .frame(width: cell.width, height: cell.height, alignment: .topLeading)
                .background(dark ? Color.black : Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, dark ? .dark : .light)
        }
        let sample = sampleTemperatureHistory()
        for dark in appearances {
            let suffix = dark ? "" : "-light"
            for window in [FanControlTemperatureWidgetSettings.HistoryWindow.oneMinute, .fiveMinutes] {
                WidgetSnapshotter.write(temperatureCell(FanControlTemperatureWidgetView(isPreview: true, previewWindow: window), dark: dark),
                                        size: cell, dark: nil,
                                        to: dir.appendingPathComponent("temperature-live-\(window.rawValue)min\(suffix).png"))
            }
            for window in FanControlTemperatureWidgetSettings.HistoryWindow.allCases {
                WidgetSnapshotter.write(temperatureCell(FanControlTemperatureWidgetView(previewHistory: sample, previewWindow: window), dark: dark),
                                        size: cell, dark: nil,
                                        to: dir.appendingPathComponent("temperature-sample-\(window.rawValue)min\(suffix).png"))
            }
        }
    }

    /// 30 min at 2 s: CPU (max) ≈ 72–80 °C with a load spike to 93 °C 3 min ago, GPU ≈ 50 °C,
    /// SSD slowly 38 → 44 °C; no samples between 20 and 17 min ago (a sleep gap).
    @MainActor static func sampleTemperatureHistory(now: Date = Date()) -> TemperatureHistory {
        var history = TemperatureHistory()
        let count = 900
        for i in 0..<count {
            let age = Double(count - 1 - i) * 2
            if age > 17 * 60 && age < 20 * 60 { continue }
            let date = now.addingTimeInterval(-age)
            let t = Double(i)
            let spike = max(0, 1 - abs(age - 180) / 70) * 17
            let cpu = 75 + 3.5 * sin(t / 9) + 1.5 * sin(t / 2.3) + spike
            let gpu = 50 + 2 * sin(t / 25) + spike * 0.35
            let ssd = 38 + 6 * t / Double(count) + 0.4 * sin(t / 40)
            history.append(cpu, for: SensorAggregator.ID.cpu, at: date)
            history.append(gpu, for: SensorAggregator.ID.gpu, at: date)
            history.append(ssd, for: "TH0x", at: date)
        }
        return history
    }
    #endif

    @MainActor static func snapshot(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (n, window) in NSApp.windows.enumerated() where window.isVisible {
            guard let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let title = window.title.isEmpty ? String(describing: type(of: window)) : window.title
            let safe = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: " ", with: "_")
            let url = dir.appendingPathComponent("\(n)-\(safe).png")
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: url)
                NSLog("[DebugHooks] wrote %@ (%@)", url.path, NSStringFromRect(window.frame))
            }
        }
    }
}
#endif
