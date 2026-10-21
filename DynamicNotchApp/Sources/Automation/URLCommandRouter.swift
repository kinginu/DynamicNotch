// F4 automation surface (2026-10-20): receives `dynamicnotch://` URLs (CFBundleURLTypes in
// project.yml; AppDelegate.application(_:open:)) and runs them through CommandRouter, one at a time
// in arrival order (a fan profile apply finishes before the next URL runs).
//
// The URL scheme has no reply channel: the outcome is logged (subsystem = bundle id, category
// "automation") and a failure beeps. `lastOutcome` keeps the latest result for debugging.
import Foundation
import AppKit
import os

@MainActor
final class URLCommandRouter {
    static let shared = URLCommandRouter()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DynamicNotch", category: "automation")
    private var queue: Task<Void, Never>?
    private(set) var lastOutcome: (url: URL, outcome: AutomationOutcome)?

    private init() {}

    /// Handles the URLs of an open request; non-`dynamicnotch` URLs are ignored.
    func handle(_ urls: [URL]) {
        for url in urls where url.scheme?.lowercased() == AutomationCommand.scheme {
            let previous = queue
            queue = Task { @MainActor in
                await previous?.value
                await self.run(url)
            }
        }
    }

    private func run(_ url: URL) async {
        let outcome = await CommandRouter.shared.perform(url: url)
        lastOutcome = (url, outcome)
        switch outcome {
        case .success(let message):
            logger.info("\(url.absoluteString, privacy: .public): \(message, privacy: .public)")
        case .failure(let error):
            logger.error("\(url.absoluteString, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            NSSound.beep()
        }
    }
}
