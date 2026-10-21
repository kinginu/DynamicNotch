import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

// Settings-list row of a shortcut
// (ShortcutsWidgetSettingsView calls it as `ShortcutItemView()`).
struct ShortcutItemView: View {
    var name: String = ""

    var body: some View {
        HStack {
            Image(systemName: "sparkles")
                .foregroundStyle(.secondary)
            Text(name)
                .lineLimit(1)
            Spacer()
        }
        .padding(.vertical, 2)
    }
}
