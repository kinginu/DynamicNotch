// ShortcutsManager — the user's shortcuts (Shortcuts.app) for the Shortcuts widget, via the
// `shortcuts` command-line tool: `refresh()` lists them (`shortcuts list`, off the main thread) and
// `run(_:completion:)` runs one (`shortcuts run <name>`).
import Foundation
import Observation
import os

private let logger = Logger(subsystem: "com.example.dynamicnotch.DynamicNotch", category: "shortcuts")

@MainActor
@Observable
final class ShortcutsManager {
    static let shared = ShortcutsManager()

    /// Names of the user's shortcuts, as `shortcuts list` prints them.
    var shortcuts: [String] = []

    /// True while `refresh()` runs.
    var isLoading = false

    nonisolated private static let tool = URL(fileURLWithPath: "/usr/bin/shortcuts")

    /// Runs `shortcuts list` off the main thread and publishes the result.
    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        let names = await Self.listShortcuts()
        if names != shortcuts { shortcuts = names }
        isLoading = false
    }

    nonisolated private static func listShortcuts() async -> [String] {
        let task = Process()
        task.executableURL = tool
        task.arguments = ["list"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
        } catch {
            logger.error("shortcuts list failed to start: \(String(describing: error), privacy: .public)")
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            logger.error("shortcuts list exited with status \(task.terminationStatus)")
        }
        return String(decoding: data, as: UTF8.self)
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Runs a shortcut by name with `shortcuts run`; `completion` gets the exit status (-1 when the
    /// tool could not be started) on the main actor.
    nonisolated static func run(_ name: String, completion: (@MainActor @Sendable (Int32) -> Void)? = nil) {
        let task = Process()
        task.executableURL = tool
        task.arguments = ["run", name]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.terminationHandler = { process in
            let status = process.terminationStatus
            if status != 0 {
                logger.error("shortcut \(name, privacy: .public) exited with status \(status)")
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { completion?(status) } }
        }
        do {
            try task.run()
        } catch {
            logger.error("shortcut \(name, privacy: .public) failed to start: \(String(describing: error), privacy: .public)")
            DispatchQueue.main.async { MainActor.assumeIsolated { completion?(-1) } }
        }
    }
}
