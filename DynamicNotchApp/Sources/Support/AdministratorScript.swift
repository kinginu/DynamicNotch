// Runs a shell script as root after the system's administrator password dialog, via
// `osascript` and AppleScript's `do shell script … with administrator privileges`. Used by the
// Fan Control helper installer (FanControlGlue/FanControlHelperInstallerAction.swift,
// docs/fan-control-integration.md "Helper installer"). No FanControl dependency, so the CLT
// harness compiles and tests it (Tests/DynamicNotchAppTests/AdministratorScriptTests.swift).
//
// Injection safety: the AppleScript source is a constant and the shell command reaches it as an
// `osascript` argument (`item 1 of argv`), never spliced into AppleScript text; in the shell
// command every word (interpreter, script, arguments, log file) is single-quoted for /bin/sh.

import Foundation

struct AdministratorScript: Equatable, Sendable {
    /// Script to run (with /bin/bash, so its executable bit does not matter).
    var scriptPath: String
    var arguments: [String]
    /// Text of the password dialog ("DynamicNotch wants to …").
    var prompt: String
    /// `false` runs the same pipeline without the password dialog, as the current user (tests).
    var withAdministratorPrivileges = true

    /// Last line of `do shell script`'s output: the script's exit status.
    static let statusMarker = "__DYNAMICNOTCH_EXIT_STATUS__="

    /// One word for /bin/sh: `'…'`, with every `'` written as `'\''`.
    static func shellQuoted(_ word: String) -> String {
        "'" + word.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// The /bin/sh command line `do shell script` runs: the script with stdin from /dev/null and
    /// stdout + stderr appended to `logPath` (which the app reads while it runs), then the exit
    /// status as a marker line on stdout. `do shell script` itself therefore always succeeds and
    /// the output survives a failure.
    func shellCommand(logPath: String) -> String {
        let words = (["/bin/bash", scriptPath] + arguments).map(Self.shellQuoted).joined(separator: " ")
        return "\(words) </dev/null >>\(Self.shellQuoted(logPath)) 2>&1; printf '\\n\(Self.statusMarker)%d\\n' \"$?\""
    }

    /// Constant AppleScript (one `-e` per line); argv = command, prompt.
    static func appleScriptLines(withAdministratorPrivileges admin: Bool) -> [String] {
        let run = admin
            ? "do shell script (item 1 of argv) with prompt (item 2 of argv) with administrator privileges without altering line endings"
            : "do shell script (item 1 of argv) without altering line endings"
        return ["on run argv", "return \(run)", "end run"]
    }

    /// Arguments of `/usr/bin/osascript`.
    func osascriptArguments(logPath: String) -> [String] {
        Self.appleScriptLines(withAdministratorPrivileges: withAdministratorPrivileges)
            .flatMap { ["-e", $0] } + [shellCommand(logPath: logPath), prompt]
    }

    // MARK: Outcome

    enum Outcome: Equatable, Sendable {
        /// The script ran; `status` is its exit status, `output` its stdout + stderr.
        case finished(status: Int32, output: String)
        /// The user cancelled the password dialog (AppleScript error -128).
        case cancelled
        /// osascript failed before or around the script (message from osascript, or ours).
        case failed(message: String, output: String)
    }

    /// Maps what osascript returned (and the log) to an outcome.
    static func outcome(osascriptStatus: Int32, stdout: String, stderr: String, log: String) -> Outcome {
        if osascriptStatus == 0 {
            guard let range = stdout.range(of: statusMarker, options: .backwards),
                  let status = Int32(stdout[range.upperBound...].prefix { $0.isNumber || $0 == "-" }) else {
                return .failed(message: "The installer returned no exit status.", output: log + stdout)
            }
            return .finished(status: status, output: log)
        }
        if stderr.contains("(-128)") { return .cancelled }
        // "0:123: execution error: <message> (<number>)" → "<message> (<number>)"
        var message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = message.range(of: "execution error: ") {
            message = String(message[range.upperBound...])
        }
        if message.isEmpty { message = "osascript exited with status \(osascriptStatus)." }
        return .failed(message: message, output: log)
    }

    // MARK: Running

    /// Runs the script: shows the password dialog (unless `withAdministratorPrivileges` is
    /// false), reports the output so far to `progress` (on the main actor) while it runs and
    /// returns the outcome. The log lives in a fresh 0700 directory of the user's temporary
    /// directory; the file is created by the app (root only appends to it), and both are
    /// removed afterwards.
    func run(progress: (@MainActor @Sendable (String) -> Void)? = nil) async -> Outcome {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("DynamicNotch-installer-\(UUID().uuidString)", isDirectory: true)
        let logURL = directory.appendingPathComponent("output.log")
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: false,
                                            attributes: [.posixPermissions: 0o700])
            guard fileManager.createFile(atPath: logURL.path, contents: Data(),
                                         attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
        } catch {
            return .failed(message: "Could not create the installer log: \(error.localizedDescription)", output: "")
        }
        defer { try? fileManager.removeItem(at: directory) }

        let readLog: @Sendable () -> String = {
            (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        }
        let arguments = osascriptArguments(logPath: logURL.path)
        let processTask = Task.detached { () -> (Int32, String, String) in
            Self.runOSAScript(arguments: arguments)
        }
        if let progress {
            var last = ""
            while !Task.isCancelled {
                let done = await Self.waitBriefly(for: processTask)
                let text = readLog()
                if text != last {
                    last = text
                    await progress(text)
                }
                if done { break }
            }
        }
        let (status, stdout, stderr) = await processTask.value
        let log = readLog()
        if let progress { await progress(log) }
        return Self.outcome(osascriptStatus: status, stdout: stdout, stderr: stderr, log: log)
    }

    /// Waits up to 0.25 s for the process task; true when it has finished.
    private static func waitBriefly(for task: Task<(Int32, String, String), Never>) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { _ = await task.value; return true }
            group.addTask { try? await Task.sleep(for: .milliseconds(250)); return false }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    /// Blocking: runs /usr/bin/osascript and returns (status, stdout, stderr).
    private static func runOSAScript(arguments: [String]) -> (Int32, String, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = arguments
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return (-1, "", "Could not run osascript: \(error.localizedDescription)")
        }
        // stderr on another thread so neither pipe can fill up and block osascript.
        let errorData = ErrorBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errorData.data = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outputData = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        return (process.terminationStatus,
                String(decoding: outputData, as: UTF8.self),
                String(decoding: errorData.data, as: UTF8.self))
    }

    private final class ErrorBox: @unchecked Sendable { var data = Data() }
}
