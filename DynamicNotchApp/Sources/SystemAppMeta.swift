import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

// A system media app: NoMediaAppsView builds it from a
// bundle identifier and MediaManager opens the app.
struct SystemAppMeta: Swift.Comparable, Equatable, Identifiable {
    var bundleId: String

    var id: String { bundleId }

    var url: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) }

    var name: String {
        guard let url else { return bundleId }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    var icon: NSImage? {
        guard let url else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    func openApp() {
        guard let url else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    static func < (lhs: SystemAppMeta, rhs: SystemAppMeta) -> Bool {
        lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}
