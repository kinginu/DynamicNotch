// Capture widget engine (2026-10-20): screenshots and screen recordings through
// /usr/sbin/screencapture (no ScreenCaptureKit code of our own).
//
//   Area      screencapture -i -s   (interactive selection; Esc cancels)
//   Window    screencapture -i -w   (interactive window pick; -o drops the shadow)
//   Screen    screencapture -m      (the main display, non-interactive)
//   Record    screencapture -v [-V <seconds>] [-k]   (main display; stopped with a character on
//             stdin — "type any character to stop" — then SIGINT, then SIGTERM as fallbacks)
//   common    -x (no sound), -t <format>, -c (clipboard, screenshots only)
//

// screenshots, reopened afterwards when the pointer is still over that notch (the closed notch plus
// a small band — not the whole open-notch canvas window: an open notch nobody hovers would
// otherwise stay open until the next hover in/out). The delay chips wait with the notch closed; if
// it was hovered open meanwhile it is closed again before screencapture runs
// (`suppressesNotchHoverOpen` tells the hover code a capture is pending). Destinations: Desktop
// (~/Desktop), Clipboard (`-c`; a recording cannot go to the clipboard, so it is saved on the
// Desktop and its file is put on the clipboard), Tray (the file is written straight into a new
// `<tray>/<UUID>/` folder and adopted by `Tray.shared`).
//
// Quitting the app ends a running screencapture (a recording is stopped and its movie delivered
// like a normal stop; a pending countdown or an interactive selection is cancelled), so no
// orphaned screencapture keeps recording. The stdin pipe never raises SIGPIPE (F_SETNOSIGPIPE): a
// stop typed after screencapture already exited just fails with EPIPE.
//
// Screen Recording permission belongs to this app (TCC attributes screencapture to the
// responsible process). Without it, screenshots contain only the wallpaper and menu bar and
// recordings fail; PermissionCenter (`.screenRecording`) drives the widget's hint.
import AppKit
import Observation
import SwiftUI

enum CaptureKind: String, CaseIterable, Identifiable {
    case area, window, screen, recording

    var id: String { rawValue }
    var isRecording: Bool { self == .recording }

    var title: String {
        switch self {
        case .area:      return String(localized: "Area")
        case .window:    return String(localized: "Window")
        case .screen:    return String(localized: "Screen")
        case .recording: return String(localized: "Record")
        }
    }

    var systemImage: String {
        switch self {
        case .area:      return "rectangle.dashed"
        case .window:    return "macwindow"
        case .screen:    return "display"
        case .recording: return "record.circle"
        }
    }
}

@MainActor
@Observable
final class CaptureManager {
    static let shared = CaptureManager()

    enum Phase: Equatable {
        case idle
        /// Waiting `delay` before the capture (notch closed); `fireDate` drives the countdown.
        case countdown(kind: CaptureKind, fireDate: Date)
        /// screencapture runs (interactive selection or a non-interactive shot).
        case capturing(CaptureKind)
        case recording(started: Date)
        /// Recording asked to stop; waiting for screencapture to finish writing the movie.
        case stopping
    }

    private(set) var phase: Phase = .idle
    /// Short feedback after a capture ("Saved to Desktop", "Cancelled", …), cleared after a while.
    private(set) var lastMessage: String?

    var isRecording: Bool {
        switch phase {
        case .recording, .stopping: return true
        default: return false
        }
    }

    var isBusy: Bool { phase != .idle }

    var recordingStart: Date? {
        if case .recording(let started) = phase { return started }
        return nil
    }

    /// The pending countdown step (cancelled by `cancelCountdown` / quit).
    @ObservationIgnored private var pendingWork: DispatchWorkItem?
    @ObservationIgnored private var messageWork: DispatchWorkItem?
    /// The running screencapture (nil while idle / counting down).
    @ObservationIgnored private var run: ScreencaptureRun?
    @ObservationIgnored private var terminateObserver: NSObjectProtocol?

    /// Time the notch's close animation needs before anything is captured.
    private static let notchCloseSettle: TimeInterval = 0.45

    private init() {
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { CaptureManager.shared.appWillTerminate() }
        }
    }

    /// A capture is counting down or screencapture runs: hovering must not open the notch (it
    /// would end up in the shot). For NotchViewModel.hoverOpenSuppressed.
    static var suppressesNotchHoverOpen: Bool {
        switch shared.phase {
        case .countdown, .capturing: return true
        default: return false
        }
    }

    // MARK: - Permission (PermissionCenter `.screenRecording`)

    /// Whether this app may capture the screen (observable through PermissionCenter).
    var hasScreenRecordingPermission: Bool { PermissionCenter.shared.isGranted(.screenRecording) }

    func refreshPermission() {
        PermissionCenter.shared.refresh(.screenRecording)
    }

    /// The system prompt the first time, the Privacy pane afterwards (PermissionCenter.request).
    func requestPermission() {
        PermissionCenter.shared.requestAccess(.screenRecording)
    }

    func openPrivacySettings() {
        PermissionCenter.shared.openSystemSettings(for: .screenRecording)
    }

    // MARK: - Starting

    /// Takes a screenshot / starts a recording of `kind`. `notch` is the notch the widget is shown
    /// in (closed first so it is not captured).
    func start(_ kind: CaptureKind, notch: DynamicNotchState?) {
        guard phase == .idle else { return }
        refreshPermission()
        let settings = SettingsStore[.captureWidgetSettings]
        let wasOpen = notch.map { $0.mode != .closed } ?? false
        if wasOpen, let notch { Self.close(notch) }
        // let the close animation finish before anything is captured
        let settle = wasOpen ? Self.notchCloseSettle : 0
        let delay = settle + TimeInterval(max(settings.delaySeconds, 0))
        phase = .countdown(kind: kind, fireDate: Date().addingTimeInterval(delay))
        afterCountdown(delay) { manager in
            if let notch, notch.mode != .closed {
                // hovered open during the countdown: close it again first (and reopen it after a
                // screenshot, as if it had been open at the start)
                Self.close(notch)
                manager.afterCountdown(Self.notchCloseSettle) { $0.launch(kind, settings: settings, notch: notch) }
            } else {
                manager.launch(kind, settings: settings, notch: wasOpen ? notch : nil)
            }
        }
    }

    /// Cancels a pending (delayed) capture.
    func cancelCountdown() {
        guard case .countdown = phase else { return }
        pendingWork?.cancel()
        pendingWork = nil
        phase = .idle
        show(String(localized: "Cancelled"))
    }

    /// Runs `step` after `delay` while still counting down (`pendingWork`; cancellable).
    private func afterCountdown(_ delay: TimeInterval, _ step: @escaping @MainActor (CaptureManager) -> Void) {
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, case .countdown = self.phase else { return }
                self.pendingWork = nil
                step(self)
            }
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private static func close(_ notch: DynamicNotchState) {
        withAnimation(.notchClose) { notch.mode = .closed }
    }

    private func launch(_ kind: CaptureKind, settings: CaptureWidgetSettings, notch: DynamicNotchState?) {
        let output = CaptureOutput.make(for: kind, settings: settings)
        let args = Self.arguments(for: kind, settings: settings, output: output)
        let run = ScreencaptureRun(kind: kind, output: output, notch: notch)
        do {
            try run.launch(arguments: args) { [weak self] run, status in
                self?.finished(run, status: status)
            }
        } catch {
            NSLog("[Capture] could not run screencapture: %@", "\(error)")
            output.discard()
            phase = .idle
            show(String(localized: "Capture failed"))
            return
        }
        self.run = run
        phase = kind.isRecording ? .recording(started: Date()) : .capturing(kind)
        NSLog("[Capture] screencapture %@", args.joined(separator: " "))
    }

    /// screencapture's arguments: options, the kind's mode, format, clipboard, then the file.
    private static func arguments(for kind: CaptureKind, settings: CaptureWidgetSettings,
                                  output: CaptureOutput) -> [String] {
        var args: [String] = []
        if !settings.playSounds { args.append("-x") }
        switch kind {
        case .area:
            args += ["-i", "-s"]
        case .window:
            args += ["-i", "-w"]
            if !settings.windowShadow { args.append("-o") }
        case .screen:
            args += ["-m"]
        case .recording:
            args += ["-v"]
            if settings.recordingLimitSeconds > 0 { args += ["-V", String(settings.recordingLimitSeconds)] }
            if settings.showClicks { args.append("-k") }
        }
        if !kind.isRecording { args += ["-t", settings.imageFormat.rawValue] }
        if case .clipboard = output { args.append("-c") }
        if let url = output.fileURL { args.append(url.path) }
        return args
    }

    // MARK: - Stopping a recording

    func stopRecording() {
        guard case .recording = phase, let run, run.isRunning else { return }
        phase = .stopping
        run.requestStop()
    }

    // MARK: - Quitting

    /// App quit: a recording is stopped (stdin, then SIGINT, then SIGTERM) and delivered before the
    /// app exits; a screenshot in progress (interactive selection) is cancelled; a countdown is
    /// dropped. Blocks the main thread for at most ~5 s, only while screencapture runs.
    private func appWillTerminate() {
        pendingWork?.cancel()
        pendingWork = nil
        guard let run else { return }
        // delivered here, synchronously: the async termination handler would never run
        let status = run.stopNow()
        _ = deliver(run, status: status)
        self.run = nil
        phase = .idle
    }

    // MARK: - Finishing

    private func finished(_ run: ScreencaptureRun, status: Int32) {
        guard self.run === run else { return }
        run.cleanUp()
        self.run = nil
        phase = .idle

        show(deliver(run, status: status))
        refreshPermission()

        // reopen the notch after a screenshot if the pointer is still over it
        if !run.kind.isRecording, let notch = run.notch, SettingsStore[.captureWidgetSettings].reopenNotch,
           notch.mode == .closed, Self.pointerIsOver(notch) {
            var mode: DynamicNotchState.NotchMode = .nook
            if case .tray(let url) = run.output, Self.exists(url) { mode = .tray }
            withAnimation(.notchOpen) { notch.select(mode) }
        }
    }

    /// Puts the result where it belongs (Tray / clipboard) and returns the feedback message.
    private func deliver(_ run: ScreencaptureRun, status: Int32) -> String {
        let failure = failureMessage(run.kind, status: status)
        switch run.output {
        case .clipboard:
            return NSPasteboard.general.changeCount != run.clipboardCount
                ? String(localized: "Copied to Clipboard") : String(localized: "Cancelled")
        case .desktop(let url):
            return Self.exists(url) ? String(localized: "Saved to Desktop") : failure
        case .desktopAndClipboard(let url):
            guard Self.exists(url) else { return failure }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([url as NSURL])
            return String(localized: "Saved to Desktop and copied")
        case .tray(let url):
            guard Self.exists(url) else {
                run.output.discard()
                return failure
            }
            Tray.shared.adoptFiles([url])
            return String(localized: "Added to Tray")
        }
    }

    /// No file: a cancelled selection, or (a recording / a failed run) missing permission.
    private func failureMessage(_ kind: CaptureKind, status: Int32) -> String {
        if (kind.isRecording || status != 0) && !hasScreenRecordingPermission {
            return String(localized: "Screen Recording permission needed")
        }
        return String(localized: "Cancelled")
    }

    private static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private func show(_ message: String) {
        messageWork?.cancel()
        lastMessage = message
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.lastMessage = nil }
        }
        messageWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    /// Whether the pointer is over the (closed) notch itself, plus a small band. Not the notch
    /// window's frame: that is the whole open-notch canvas, a wide transparent strip below and
    /// beside the camera housing, where a selection often ends without the notch being hovered.
    private static func pointerIsOver(_ notch: DynamicNotchState) -> Bool {
        guard let id = DynamicNotchState.perScreen.first(where: { $0.value === notch })?.key,
              let kit = WindowsManager.shared.displayKits[id],
              let window = kit.dynamicnotchWindow else { return false }
        let size = kit.screen.hardwareNotchSize
        let f = window.frame
        let band: CGFloat = 12
        let region = CGRect(x: f.midX - size.width / 2 - band, y: f.maxY - size.height - band,
                            width: size.width + 2 * band, height: size.height + band + 1)
        return region.contains(NSEvent.mouseLocation)
    }

    /// `<dir>/<name>.<ext>`, or `<name> (2).<ext>` … when that file exists.
    nonisolated static func uniqueURL(in dir: URL, name: String, ext: String) -> URL {
        var url = dir.appendingPathComponent("\(name).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(name) (\(n)).\(ext)")
            n += 1
        }
        return url
    }

    #if DEBUG
    /// DEBUG (snapshots): put the manager in a phase without running anything.
    func debugSetPhase(_ phase: Phase, message: String? = nil) {
        self.phase = phase
        self.lastMessage = message
    }
    #endif
}

// MARK: - One screencapture run

/// A running /usr/sbin/screencapture and what it produces. Main actor only (the termination
/// handler hops to the main queue).
@MainActor
private final class ScreencaptureRun {
    private static let tool = URL(fileURLWithPath: "/usr/sbin/screencapture")
    /// "type any character to stop" (recordings).
    private static let stopCharacter = Data("q\n".utf8)

    let kind: CaptureKind
    let output: CaptureOutput
    /// The notch to reopen after a screenshot (nil: leave it closed).
    let notch: DynamicNotchState?
    /// NSPasteboard change count before the run (a clipboard shot changes it).
    let clipboardCount = NSPasteboard.general.changeCount

    private let process = Process()
    private let stdin = Pipe()
    /// SIGINT / SIGTERM fallbacks of `requestStop()`.
    private var stopEscalation: [DispatchWorkItem] = []

    init(kind: CaptureKind, output: CaptureOutput, notch: DynamicNotchState?) {
        self.kind = kind
        self.output = output
        self.notch = notch
    }

    var isRunning: Bool { process.isRunning }

    /// Starts screencapture; `onExit` runs on the main actor with its termination status.
    func launch(arguments: [String], onExit: @escaping @MainActor (ScreencaptureRun, Int32) -> Void) throws {
        process.executableURL = Self.tool
        process.arguments = arguments
        // a write after screencapture exited (e.g. its -V limit ran out as Stop is pressed) fails
        // with EPIPE instead of raising SIGPIPE, which would kill the app
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        process.standardInput = stdin
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] p in
            let status = p.terminationStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    onExit(self, status)
                }
            }
        }
        try process.run()
    }

    /// Stops a recording: 1. the stop character on stdin; 2. SIGINT (ctrl-C) after 1.5 s;
    /// 3. SIGTERM after 8 s.
    func requestStop() {
        sendStopCharacter()
        let process = self.process
        let interrupt = DispatchWorkItem { if process.isRunning { process.interrupt() } }
        let terminate = DispatchWorkItem { if process.isRunning { process.terminate() } }
        stopEscalation = [interrupt, terminate]
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: interrupt)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: terminate)
    }

    /// Quit: ends screencapture synchronously (a recording: stop character ≤ 3 s, SIGINT ≤ 1 s;
    /// then SIGTERM ≤ 1 s) and returns its status (-1 when it is still running). The termination
    /// handler is dropped — the caller delivers the result.
    func stopNow() -> Int32 {
        process.terminationHandler = nil
        if process.isRunning {
            if kind.isRecording {
                sendStopCharacter()
                waitForExit(3)
                if process.isRunning { process.interrupt(); waitForExit(1) }
            }
            if process.isRunning { process.terminate(); waitForExit(1) }
        }
        let status = process.isRunning ? -1 : process.terminationStatus
        cleanUp()
        return status
    }

    /// Cancels the stop fallbacks and closes stdin.
    func cleanUp() {
        stopEscalation.forEach { $0.cancel() }
        stopEscalation = []
        try? stdin.fileHandleForWriting.close()
    }

    private func sendStopCharacter() {
        try? stdin.fileHandleForWriting.write(contentsOf: Self.stopCharacter)
    }

    private func waitForExit(_ seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while process.isRunning && Date() < deadline { usleep(50_000) }
    }
}

// MARK: - Output

/// Where one capture's result goes.
private enum CaptureOutput {
    case clipboard
    case desktop(URL)
    case desktopAndClipboard(URL)
    case tray(URL)

    /// The destination for `kind` under `settings` (a Tray capture gets a new item folder; a
    /// recording cannot go to the clipboard, so it is saved on the Desktop and its file copied).
    @MainActor static func make(for kind: CaptureKind, settings: CaptureWidgetSettings) -> CaptureOutput {
        let ext = kind.isRecording ? "mov" : settings.imageFormat.rawValue
        let name = settings.fileName(kind: kind)
        switch settings.destination {
        case .clipboard where !kind.isRecording:
            return .clipboard
        case .tray:
            return .tray(Tray.shared.newItemDirectory().appendingPathComponent("\(name).\(ext)"))
        case .desktop, .clipboard:
            let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop")
            let url = CaptureManager.uniqueURL(in: desktop, name: name, ext: ext)
            return settings.destination == .clipboard ? .desktopAndClipboard(url) : .desktop(url)
        }
    }

    var fileURL: URL? {
        switch self {
        case .clipboard: return nil
        case .desktop(let u), .desktopAndClipboard(let u), .tray(let u): return u
        }
    }

    /// Removes the empty tray folder of a capture that produced no file.
    func discard() {
        if case .tray(let url) = self, !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
    }
}
