// AdministratorScript (the shell command / osascript construction, its injection safety, the
// outcome mapping) and HelperInstallerCommands, without administrator privileges: the
// end-to-end tests run the same osascript pipeline with `withAdministratorPrivileges = false`
// against FanControl's real install.sh in its no-root modes (--help, --dry-run).
import Foundation
import Testing
@testable import DynamicNotchApp

@Suite("Administrator script (helper installer)")
struct AdministratorScriptTests {
    /// Words that break naive quoting: quotes, command substitution, globbing, newlines.
    static let nastyWords = [
        "/Applications/DynamicNotch.app",
        "/Users/a b/My Apps/Dynamic Notch.app",
        "/tmp/it's here.app",
        #"/tmp/"double" \back\slash.app"#,
        "/tmp/$(touch /tmp/pwned).app",
        "/tmp/`id`;rm -rf ~;.app",
        "/tmp/*?[a].app",
        "/tmp/line\nbreak.app",
        "-n",
        "",
    ]

    static var manualInstallDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // DynamicNotchAppTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // DynamicNotchApp
            .deletingLastPathComponent()   // repository root
            .appendingPathComponent("FanControl/Support/manual-install", isDirectory: true)
    }

    static var hasManualInstallScripts: Bool {
        FileManager.default.fileExists(atPath: manualInstallDirectory.appendingPathComponent("install.sh").path)
    }

    /// Runs `/bin/sh -c command`; returns (status, stdout).
    static func sh(_ command: String) throws -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        let out = Pipe()
        process.standardOutput = out
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AdministratorScriptTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: Construction

    @Test("shellQuoted survives /bin/sh unchanged", arguments: nastyWords)
    func quotingRoundTrip(word: String) throws {
        let (status, output) = try Self.sh("printf '%s' \(AdministratorScript.shellQuoted(word))")
        #expect(status == 0)
        #expect(output == word)
    }

    @Test("The shell command passes every argument as one word and reports the exit status")
    func shellCommandArguments() throws {
        let dir = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        // A script that prints each argument followed by NUL, then exits with 7.
        let script = dir.appendingPathComponent("print args.sh")
        try #"for a in "$@"; do printf '%s\0' "$a"; done; exit 7"#.write(to: script, atomically: true, encoding: .utf8)
        let log = dir.appendingPathComponent("it's.log")
        FileManager.default.createFile(atPath: log.path, contents: Data())
        let pwned = dir.appendingPathComponent("pwned")
        let arguments = Self.nastyWords + ["$(touch \(pwned.path))", "`touch \(pwned.path)`"]
        let command = AdministratorScript(scriptPath: script.path, arguments: arguments, prompt: "p")
            .shellCommand(logPath: log.path)

        let (status, stdout) = try Self.sh(command)
        #expect(status == 0)                     // do shell script itself succeeds…
        #expect(stdout.hasSuffix("\n\(AdministratorScript.statusMarker)7\n"))   // …and reports 7
        let printed = try String(contentsOf: log, encoding: .utf8)
        #expect(printed.split(separator: "\0", omittingEmptySubsequences: false).dropLast().map(String.init) == arguments)
        #expect(!FileManager.default.fileExists(atPath: pwned.path))
    }

    @Test("The AppleScript is constant; command and prompt are osascript arguments")
    func osascriptArguments() {
        let script = AdministratorScript(scriptPath: "/tmp/x\"y.sh", arguments: ["/tmp/a\" & (do shell script \"id\") & \".app"],
                                         prompt: "Prompt \"quoted\"")
        let args = script.osascriptArguments(logPath: "/tmp/log")
        let lines = AdministratorScript.appleScriptLines(withAdministratorPrivileges: true)
        #expect(Array(args.prefix(lines.count * 2)) == lines.flatMap { ["-e", $0] })
        #expect(args.suffix(2) == [script.shellCommand(logPath: "/tmp/log"), "Prompt \"quoted\""])
        #expect(lines.joined().contains("with administrator privileges"))
        #expect(!lines.joined().contains("/tmp"))
        #expect(!AdministratorScript.appleScriptLines(withAdministratorPrivileges: false).joined().contains("administrator"))
    }

    // MARK: Outcome mapping

    @Test("osascript results map to outcomes")
    func outcomes() {
        let marker = AdministratorScript.statusMarker
        #expect(AdministratorScript.outcome(osascriptStatus: 0, stdout: "\n\(marker)0\n\n", stderr: "", log: "done\n")
                == .finished(status: 0, output: "done\n"))
        #expect(AdministratorScript.outcome(osascriptStatus: 0, stdout: "\n\(marker)1\n\n", stderr: "", log: "error: x\n")
                == .finished(status: 1, output: "error: x\n"))
        #expect(AdministratorScript.outcome(osascriptStatus: 1, stdout: "",
                                            stderr: "0:120: execution error: User canceled. (-128)\n", log: "")
                == .cancelled)
        #expect(AdministratorScript.outcome(osascriptStatus: 1, stdout: "",
                                            stderr: "0:120: execution error: The administrator user name or password was incorrect. (-60007)\n", log: "")
                == .failed(message: "The administrator user name or password was incorrect. (-60007)", output: ""))
        if case .failed = AdministratorScript.outcome(osascriptStatus: 0, stdout: "no marker", stderr: "", log: "") {} else {
            Issue.record("a missing status marker must be a failure")
        }
    }

    @Test("Installer results: output on success, the script's error line on failure, cancel")
    func installerResults() throws {
        #expect(try HelperInstallerCommands.result(of: .finished(status: 0, output: "ok")) == "ok")
        let output = "==> Verifying\nerror: app signature is invalid: /x.app\n"
        #expect(throws: HelperInstallerCommands.Failure(summary: "The helper installer failed: app signature is invalid: /x.app", output: output)) {
            try HelperInstallerCommands.result(of: .finished(status: 1, output: output))
        }
        #expect(throws: HelperInstallerCommands.Failure(summary: "The helper installer failed (exit status 2).", output: "")) {
            try HelperInstallerCommands.result(of: .finished(status: 2, output: ""))
        }
        #expect(throws: CancellationError.self) {
            try HelperInstallerCommands.result(of: .cancelled)
        }
    }

    @Test("Installer commands: bundled scripts with --app <this app>")
    func installerCommands() {
        let app = "/Applications/Dynamic Notch's.app"
        let commands = HelperInstallerCommands(scriptsDirectory: "\(app)/Contents/Resources/manual-install", appPath: app)
        #expect(commands.install.scriptPath == "\(app)/Contents/Resources/manual-install/install.sh")
        #expect(commands.uninstall.scriptPath == "\(app)/Contents/Resources/manual-install/uninstall.sh")
        #expect(commands.install.arguments == ["--app", app])
        #expect(commands.uninstall.arguments == ["--app", app])
        #expect(commands.install.withAdministratorPrivileges)
        #expect(HelperInstallerCommands(bundle: Bundle(for: BundleToken.self)) == nil)   // test bundle: no scripts
    }

    // MARK: End to end (no administrator privileges)

    @Test("install.sh --help through osascript", .enabled(if: hasManualInstallScripts))
    func endToEndHelp() async throws {
        var script = HelperInstallerCommands(scriptsDirectory: Self.manualInstallDirectory.path, appPath: "/x.app").install
        script.arguments = ["--help"]
        script.withAdministratorPrivileges = false
        let outcome = await script.run()
        guard case .finished(0, let output) = outcome else {
            Issue.record("unexpected outcome \(outcome)")
            return
        }
        #expect(output.contains("usage:"))
    }

    @Test("install.sh --dry-run with a hostile app path fails cleanly", .enabled(if: hasManualInstallScripts))
    @MainActor func endToEndDryRun() async throws {
        let dir = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pwned = dir.appendingPathComponent("pwned")
        let app = dir.appendingPathComponent("It's $(touch \(pwned.path)) `touch \(pwned.path)`.app").path
        var script = HelperInstallerCommands(scriptsDirectory: Self.manualInstallDirectory.path, appPath: app).install
        script.arguments = ["--dry-run"] + script.arguments
        script.withAdministratorPrivileges = false
        let collected = ProgressLog()
        let outcome = await script.run { collected.text = $0 }
        guard case .finished(let status, let output) = outcome else {
            Issue.record("unexpected outcome \(outcome)")
            return
        }
        #expect(status != 0)
        #expect(output.contains("error: "))
        #expect(output.contains(app))            // the path reached the script as one word
        #expect(collected.text == output)
        #expect(!FileManager.default.fileExists(atPath: pwned.path))
        #expect(throws: HelperInstallerCommands.Failure.self) { try HelperInstallerCommands.result(of: outcome) }
    }
}

private final class BundleToken {}

@MainActor private final class ProgressLog: Sendable {
    var text = ""
}
