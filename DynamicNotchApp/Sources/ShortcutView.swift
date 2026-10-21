import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

// Button that runs a
// Shortcuts.app shortcut by name (ShortcutsRowView passes `shortcutIdentifier:`).
struct ShortcutView: View {
    var shortcutIdentifier: String

    var body: some View {
        Button {
            ShortcutView.run(shortcutIdentifier)
        } label: {
            Text(shortcutIdentifier)
                .lineLimit(1)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    // runs `/usr/bin/shortcuts run <name>`
    static func run(_ name: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        task.arguments = ["run", name]
        try? task.run()
    }
}
