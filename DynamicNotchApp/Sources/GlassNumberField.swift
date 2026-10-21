import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import AppKit
import Foundation
import SwiftUI

// NSViewRepresentable wrapping NSTextField for numeric input
//   with glass-style formatting. Parses Double from stringValue, clamps
//   to range [lowerBound, upperBound], and updates binding.
struct GlassNumberField: NSViewRepresentable {

    // MARK: - Properties

    @Binding var value: Double

    // Lower bound for clamping (read from parent's range)
    var lowerBound: Double

    // Upper bound for clamping
    var upperBound: Double

    // MARK: - Static Helper

    static func format(_ value: Double) -> String {
        return String(format: "%.3g", value)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: GlassNumberField

        init(parent: GlassNumberField) {
            self.parent = parent
        }

        @objc func controlTextDidEndEditing(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            commit(textField)
        }

        // Parses the text (thousands separators removed), clamps it to [lowerBound, upperBound],
        //   updates the binding, then shows the formatted current value.
        func commit(_ textField: NSTextField) {
            let raw = textField.stringValue

            let sanitized = raw.replacingOccurrences(of: ",", with: "")

            if let parsed = Double(sanitized) {
                var clamped = parsed
                if clamped < parent.lowerBound {
                    clamped = parent.lowerBound
                }
                if clamped > parent.upperBound {
                    clamped = parent.upperBound
                }

                parent.value = clamped
            }

            // also reverts the text when parsing failed
            let formatted = GlassNumberField.format(parent.value)
            textField.stringValue = formatted
        }
    }

    // MARK: - NSViewRepresentable

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()

        textField.alignment = .left

        textField.font = NSFont.monospacedDigitSystemFont(ofSize: 0, weight: .regular)

        textField.isBezeled = true
        textField.bezelStyle = .squareBezel
        textField.isEditable = true

        textField.delegate = context.coordinator

        textField.stringValue = GlassNumberField.format(value)

        return textField
    }

    // Leaves the field alone while it is being edited.
    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.currentEditor() != nil {
            return
        }

        nsView.stringValue = GlassNumberField.format(value)
    }
}
