// The Fan Control helper installer bundled in the app: FanControl's manual-install scripts in
// Contents/Resources/manual-install/ (project.yml), run as root with this app's path
// (AdministratorScript). Used by FanControlGlue/FanControlHelperInstallerAction.swift; no
// FanControl dependency, so the CLT harness tests it (Tests/DynamicNotchAppTests/
// AdministratorScriptTests.swift). docs/fan-control-integration.md "Helper installer".

import Foundation

struct HelperInstallerCommands: Equatable, Sendable {
    /// Folder inside Contents/Resources.
    static let directoryName = "manual-install"

    let install: AdministratorScript
    let uninstall: AdministratorScript

    /// `install.sh --app <app>` / `uninstall.sh --app <app>` from `scriptsDirectory`.
    init(scriptsDirectory: String, appPath: String) {
        let directory = URL(fileURLWithPath: scriptsDirectory, isDirectory: true)
        install = AdministratorScript(
            scriptPath: directory.appendingPathComponent("install.sh").path,
            arguments: ["--app", appPath],
            prompt: String(localized: "DynamicNotch wants to install its fan control helper."))
        uninstall = AdministratorScript(
            scriptPath: directory.appendingPathComponent("uninstall.sh").path,
            arguments: ["--app", appPath],
            prompt: String(localized: "DynamicNotch wants to remove its fan control helper."))
    }

    /// The scripts bundled in `bundle` (nil when they are missing, e.g. in a test bundle).
    init?(bundle: Bundle) {
        guard let resources = bundle.resourceURL?.appendingPathComponent(Self.directoryName, isDirectory: true),
              FileManager.default.fileExists(atPath: resources.appendingPathComponent("install.sh").path),
              FileManager.default.fileExists(atPath: resources.appendingPathComponent("uninstall.sh").path) else {
            return nil
        }
        self.init(scriptsDirectory: resources.path, appPath: bundle.bundleURL.path)
    }

    /// A failed run: `summary` for the error line, `output` for the log.
    struct Failure: Error, Equatable {
        var summary: String
        var output: String
    }

    /// The script's output when it exited with 0; throws `CancellationError` when the user
    /// cancelled the password dialog, `Failure` otherwise.
    static func result(of outcome: AdministratorScript.Outcome) throws -> String {
        switch outcome {
        case .finished(0, let output):
            return output
        case .finished(let status, let output):
            if let line = lastErrorLine(in: output) {
                throw Failure(summary: String(localized: "The helper installer failed: \(line)"), output: output)
            }
            throw Failure(summary: String(localized: "The helper installer failed (exit status \(Int(status)))."), output: output)
        case .cancelled:
            throw CancellationError()
        case .failed(let message, let output):
            throw Failure(summary: String(localized: "The helper installer could not run: \(message)"), output: output)
        }
    }

    /// The last `error: …` line the scripts print (lib.sh `die`), without the prefix.
    static func lastErrorLine(in output: String) -> String? {
        output.split(whereSeparator: \.isNewline)
            .last { $0.hasPrefix("error: ") }
            .map { String($0.dropFirst("error: ".count)) }
    }
}
