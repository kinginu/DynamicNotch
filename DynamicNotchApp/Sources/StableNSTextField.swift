import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import AppKit
import Foundation
import SwiftUI

// NSViewRepresentable wrapping an NSTextField subclass that
//   fires onChange callback when text changes. "Stable" means it avoids
//   feedback loops by comparing old/new values before propagating.
struct StabelNSTextField: NSViewRepresentable {

    // MARK: - Properties

    // Bound text value
    @Binding var text: String

    // Placeholder string
    var placeholder: String = ""

    // Called when text changes
    var onChange: ((String) -> Void)?

    // MARK: - Coordinator

    class Coordinator: NSObject {
        var parent: StabelNSTextField

        init(parent: StabelNSTextField) {
            self.parent = parent
        }

        @MainActor
        @objc func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            parent.onChange?(textField.stringValue)
        }

        @MainActor
        @objc func controlTextDidBeginEditing(_ notification: Notification) {
            // No-op in the original; placeholder for begin editing hook
        }
    }

    // MARK: - NSViewRepresentable

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> StabelTextField {
        let textField = StabelTextField()

        // Standard NSTextField setup
        textField.placeholderString = placeholder
        textField.stringValue = text
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.isEditable = true
        textField.isSelectable = true

        // Wire coordinator for text change notifications
        textField.target = context.coordinator
        textField.action = #selector(Coordinator.controlTextDidChange(_:))

        return textField
    }

    func updateNSView(_ nsView: StabelTextField, context: Context) {
        // Only update if value differs to avoid feedback loop
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }
}

// MARK: - StabelTextField (NSView subclass)

// Custom NSTextField subclass — the NSViewType for StabelNSTextField
class StabelTextField: NSTextField {
    // Minimal subclass; behavior is handled by the coordinator
}
