#if os(macOS)
// Part of DynamicNotch's Fan Control glue (Sources/FanControlGlue/): the "Install Helper…" /
// "Uninstall Helper…" buttons of Settings ▸ Fan Control ▸ General
// (docs/fan-control-integration.md "Helper installer").
//
// The app bundles FanControl's manual-install scripts in Contents/Resources/manual-install/
// (project.yml). The buttons run install.sh / uninstall.sh from there with this app's path,
// as root, after the system's administrator password dialog (AdministratorScript). The script
// pins the helper to this build's cdhash, so it has to run again after every update.

import Foundation
import FanControlUI

@MainActor
enum FanControlHelperInstallerAction {
    /// Registers the host actions (fan-control-integration.md (e)). Leaves them unset when the
    /// scripts are missing from the bundle, so the pane falls back to its default UI.
    static func register(bundle: Bundle = .main) {
        guard let commands = HelperInstallerCommands(bundle: bundle) else { return }
        FanControlHostActions.installHelper = { progress in
            try await run(commands.install, progress: progress)
        }
        FanControlHostActions.uninstallHelper = { progress in
            try await run(commands.uninstall, progress: progress)
        }
    }

    private static func run(_ script: AdministratorScript,
                            progress: @escaping @MainActor (String) -> Void) async throws -> String {
        let outcome = await script.run { progress($0) }
        do {
            return try HelperInstallerCommands.result(of: outcome)
        } catch let failure as HelperInstallerCommands.Failure {
            throw FanControlHelperInstallerFailure(summary: failure.summary, output: failure.output)
        }
    }
}
#endif
