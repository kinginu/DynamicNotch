// DEBUG-only command registry (2026-10-20, R15): the single entry point of every debug
// command. Before this, each widget's debug file installed its own DistributedNotificationCenter
// observer (a dozen listeners, most of them only after the widget had appeared once). Now:
//
//   • one listener on `DebugHooks.notificationName` ("com.example.dynamicnotch.debug", or
//     "…debug.<DN_DEBUG_CHANNEL>"), installed by `DebugHooks.install()` at launch;
//   • every command is a registration: `DebugCommandRegistry.register("netlog") { arg in … }`
//     (arg = everything after the first ":" of the command string, "" when there is none). The
//     per-widget files (Support/DebugHooks-*.swift, BluetoothWidgetDebug.swift,
//     WidgetGallery-Debug.swift) only register; `DebugHooks.install()` registers all of them up
//     front, so every command works right after launch (no "open the widget once first");
//   • `help` lists every command (`help:<filter>` narrows, `help:/path/file.txt` writes the list to
//     a file);
//   • two delivery paths that do not need distributed notifications (one agent saw them not arrive):
//       -DNDebugCommand <name:arg>      launch argument, repeatable; run in order ~2 s after launch
//                                       (-DNDebugCommandDelay <seconds> changes the delay)
//       -DNDebugCommandFile <path>      (or DN_DEBUG_COMMAND_FILE=<path>) a text file polled every
//                                       0.5 s; every new line is a command (append to send more)
//     Both run sequentially and understand the built-ins `wait:<seconds>` and `quit`.
//   • Tools/dn-debug.sh sends commands to a channel (notification or command file).
//
// Built-ins: help[:<filter>|<file>], ping[:<file>], echo:<text>, wait:<seconds>, quit.
// Commands that still have their own listener in files outside the debug area (see
// `legacyVerbs`) are listed by `help`; from the launch-argument / file paths they are re-posted as
// distributed notifications (best effort) so those listeners see them too.
#if DEBUG
import AppKit

@MainActor
enum DebugCommandRegistry {
    typealias Handler = @MainActor (_ arg: String) -> Void

    struct Command {
        let name: String
        /// e.g. "netpreview:<dir>" (shown by `help`; defaults to the name)
        let usage: String
        let summary: String
        /// The registering file (from #fileID), e.g. "DebugHooks-Network"
        let group: String
        let handler: Handler
    }

    /// Where a command came from (only changes how legacy verbs are treated).
    enum Source: String { case notification, launchArgument = "launch", commandFile = "file", code }

    private(set) static var commands: [String: Command] = [:]

    // MARK: Registration

    /// Registers (or replaces) the command `name`. `usage` defaults to `name`.
    static func register(_ name: String, usage: String? = nil, _ summary: String = "",
                         file: String = #fileID, _ handler: @escaping Handler) {
        let group = (file.split(separator: "/").last.map(String.init) ?? file).replacingOccurrences(of: ".swift", with: "")
        if let existing = commands[name], existing.group != group {
            NSLog("[DebugHooks] command %@ re-registered by %@ (was %@)", name, group, existing.group)
        }
        commands[name] = Command(name: name, usage: usage ?? name, summary: summary, group: group, handler: handler)
    }

    /// Commands that are still handled by their own DistributedNotificationCenter observer in a file
    /// outside the debug area (not owned by the debug hooks; migrate them to `register` when those
    /// files are next touched). The registry ignores them when they arrive as notifications.
    static let legacyVerbs: [String: String] = [
        "timergallery": "timergallery:<dir>  (TimerWidgetView.swift, listener installed when the Timer widget appears)",
        "timerpresets": "timerpresets:<dir>  (TimerWidgetSettingsView.swift, installed when the timer creator appears)",
        "pomodorogallery": "pomodorogallery:<dir>  (PomodoroWidgetView.swift, installed by PomodoroStore)",
        "mirrorpreview": "mirrorpreview:<dir>  (MirrorWidgetView.swift, installed when the Camera widget appears)",
        "rowwidgets": "rowwidgets:<dir>  (ShortcutsWidgetView.swift, installed when Shortcuts / Quick Apps appear)",
        "hoverprobe": "hoverprobe:in|out|stop|state  (NotchHover+Debug.swift)",
        "notchgeom": "notchgeom[:aspect=<w/h>]  (NotchHover+Debug.swift)",
    ]

    // MARK: Dispatch

    static func split(_ command: String) -> (verb: String, arg: String) {
        guard let i = command.firstIndex(of: ":") else { return (command, "") }
        return (String(command[..<i]), String(command[command.index(after: i)...]))
    }

    /// Runs one command string. Returns false for an unknown verb.
    @discardableResult
    static func dispatch(_ command: String, source: Source = .code) -> Bool {
        let command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty, !command.hasPrefix("#") else { return true }
        let (verb, arg) = split(command)
        if let entry = commands[verb] {
            NSLog("[DebugHooks] %@", command)
            entry.handler(arg)
            return true
        }
        if legacyVerbs[verb] != nil {
            // Their own observers already received a notification; other paths are re-posted.
            if source != .notification {
                NSLog("[DebugHooks] %@ → re-posted for its own listener", command)
                DistributedNotificationCenter.default().postNotificationName(
                    DebugHooks.notificationName, object: command, userInfo: nil, deliverImmediately: true)
            }
            return true
        }
        NSLog("[DebugHooks] unknown command %@ (send `help` for the list)", command)
        return false
    }

    // MARK: Listener

    private static var observer: NSObjectProtocol?

    /// The one distributed-notification observer of the debug hooks.
    nonisolated static func installListener() {
        MainActor.assumeIsolated {
            guard observer == nil else { return }
            observer = DistributedNotificationCenter.default().addObserver(
                forName: DebugHooks.notificationName, object: nil, queue: .main
            ) { note in
                guard let command = note.object as? String else { return }
                MainActor.assumeIsolated { _ = dispatch(command, source: .notification) }
            }
            NSLog("[DebugHooks] listening on %@ (%ld commands; send `help`)", DebugHooks.notificationName.rawValue, commands.count)
        }
    }

    // MARK: Sequential paths (launch arguments, command file)

    private static var queue: [(String, Source)] = []
    private static var pumping = false

    static func enqueue(_ list: [String], source: Source) {
        queue.append(contentsOf: list.map { ($0, source) })
        guard !pumping else { return }
        pumping = true
        Task { @MainActor in
            while !queue.isEmpty {
                let (command, source) = queue.removeFirst()
                let (verb, arg) = split(command.trimmingCharacters(in: .whitespacesAndNewlines))
                if verb == "wait" {
                    NSLog("[DebugHooks] wait %@ s", arg)
                    try? await Task.sleep(nanoseconds: UInt64(max(0, Double(arg) ?? 1) * 1_000_000_000))
                } else {
                    dispatch(command, source: source)
                    await Task.yield()
                }
            }
            pumping = false
        }
    }

    /// `-DNDebugCommand <cmd>` (repeatable) → run in order after `-DNDebugCommandDelay` (2 s).
    static func runLaunchArguments(_ arguments: [String] = CommandLine.arguments) {
        var list: [String] = []
        var delay: TimeInterval = 2
        var file = ProcessInfo.processInfo.environment["DN_DEBUG_COMMAND_FILE"]
        var i = arguments.startIndex
        while i < arguments.endIndex {
            let a = arguments[i]
            let next = arguments.index(after: i) < arguments.endIndex ? arguments[arguments.index(after: i)] : nil
            switch a {
            case "-DNDebugCommand":
                if let next { list.append(next); i = arguments.index(after: i) }
            case "-DNDebugCommandDelay":
                if let next { delay = TimeInterval(next) ?? delay; i = arguments.index(after: i) }
            case "-DNDebugCommandFile":
                if let next { file = next; i = arguments.index(after: i) }
            default:
                break
            }
            i = arguments.index(after: i)
        }
        if let file, !file.isEmpty { watchCommandFile(file, after: delay) }
        guard !list.isEmpty else { return }
        NSLog("[DebugHooks] %ld launch command(s) in %.1f s", list.count, delay)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated { enqueue(list, source: .launchArgument) }
        }
    }

    private static var fileTimer: Timer?
    private static var fileOffset: UInt64 = 0

    /// Polls `path` every 0.5 s and runs every complete new line (from the start of the file).
    static func watchCommandFile(_ path: String, after delay: TimeInterval) {
        guard fileTimer == nil else { return }
        let path = (path as NSString).expandingTildeInPath
        NSLog("[DebugHooks] command file %@", path)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated {
                let timer = Timer(timeInterval: 0.5, repeats: true) { _ in
                    MainActor.assumeIsolated { readCommandFile(path) }
                }
                RunLoop.main.add(timer, forMode: .common)
                fileTimer = timer
            }
        }
    }

    private static func readCommandFile(_ path: String) {
        guard let handle = FileHandle(forReadingAtPath: path) else { return }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        if size < fileOffset { fileOffset = 0 } // truncated / replaced
        guard size > fileOffset else { return }
        try? handle.seek(toOffset: fileOffset)
        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8),
              let lastNewline = text.lastIndex(of: "\n") else { return }
        let complete = text[..<lastNewline]
        fileOffset += UInt64(complete.utf8.count + 1)
        let lines = complete.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        if !lines.isEmpty { enqueue(lines, source: .commandFile) }
    }

    // MARK: Built-ins

    static func registerBuiltins() {
        register("help", usage: "help[:<filter>|<file>]",
                 "list every command (a filter keeps names/usages containing it; an absolute path writes the list there)") { arg in
            let isFile = arg.hasPrefix("/") || arg.hasPrefix("~")
            let text = helpText(filter: isFile ? "" : arg)
            if isFile {
                let path = (arg as NSString).expandingTildeInPath
                try? text.write(toFile: path, atomically: true, encoding: .utf8)
                NSLog("[DebugHooks] help written to %@", path)
                return
            }
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) { NSLog("[help] %@", String(line)) }
        }
        register("ping", usage: "ping[:<file>]", "log (and write to <file>) \"pong <channel> <pid>\" — checks delivery") { arg in
            let line = "pong \(DebugHooks.notificationName.rawValue) \(ProcessInfo.processInfo.processIdentifier)"
            NSLog("[DebugHooks] %@", line)
            if !arg.isEmpty { try? (line + "\n").write(toFile: (arg as NSString).expandingTildeInPath, atomically: true, encoding: .utf8) }
        }
        register("echo", usage: "echo:<text>", "log <text> (a marker in the log stream)") { arg in
            NSLog("[DebugHooks] echo %@", arg)
        }
        register("wait", usage: "wait:<seconds>", "pause a launch-argument / command-file sequence (no-op as a notification)") { _ in }
        register("quit", "terminate this (development) instance") { _ in
            NSApp.terminate(nil)
        }
    }

    static func helpText(filter: String = "") -> String {
        let f = filter.lowercased()
        func keep(_ s: String) -> Bool { f.isEmpty || s.lowercased().contains(f) }
        var lines = ["DynamicNotch debug commands on \(DebugHooks.notificationName.rawValue)",
                     "(send with Tools/dn-debug.sh, -DNDebugCommand <cmd>, or a -DNDebugCommandFile line)"]
        let groups = Dictionary(grouping: commands.values, by: \.group)
        for group in groups.keys.sorted() {
            let entries = groups[group]!.filter { keep($0.name) || keep($0.usage) || keep($0.summary) }.sorted { $0.name < $1.name }
            guard !entries.isEmpty else { continue }
            lines.append("")
            lines.append("[\(group)]")
            for c in entries {
                lines.append("  " + c.usage.padding(toLength: max(c.usage.count, 30), withPad: " ", startingAt: 0)
                             + (c.summary.isEmpty ? "" : "  " + c.summary))
            }
        }
        let legacy = legacyVerbs.filter { keep($0.key) || keep($0.value) }.sorted { $0.key < $1.key }
        if !legacy.isEmpty {
            lines.append("")
            lines.append("[own listeners outside the debug area — not yet registrations]")
            for (_, usage) in legacy { lines.append("  " + usage) }
        }
        lines.append("")
        lines.append("Snapshot commands (*preview:<dir>, widgetgallery:<dir>) accept options: <dir>?appearance=dark|light|both&glass=off|on|both&settle=<s>")
        return lines.joined(separator: "\n")
    }
}
#endif
