import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import AppKit
import Foundation
import SwiftUI

//   controlTextDidChange (~200 bytes)
// NSViewRepresentable wrapping NSTextField for integer numeric input.
//   Formats as "%.0f", parses with strtod, clamps to [lowerBound, upperBound],
//   and updates binding.
struct IntegerTextField: NSViewRepresentable {

    // MARK: - Properties

    // Bound value as Double (integer displayed with no decimal places)
    @Binding var value: Double

    // Lower bound for clamping
    var lowerBound: Double

    // Upper bound for clamping
    var upperBound: Double

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextFieldDelegate { // NSTextFieldDelegate conformance
        var parent: IntegerTextField

        init(parent: IntegerTextField) {
            self.parent = parent
        }

        @objc func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }

            let raw = textField.stringValue

            if let parsed = Double(raw) {
                var clamped = parsed
                if clamped < parent.lowerBound {
                    clamped = parent.lowerBound
                }
                if clamped > parent.upperBound {
                    clamped = parent.upperBound
                }

                parent.value = clamped
            }
        }
    }

    // MARK: - NSViewRepresentable

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    //   Creates NSTextField with:
    //     alignment = 2 (.right)
    //     setDelegate(coordinator), setBezeled(true), setEditable(true)
    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()

        textField.alignment = .right

        textField.font = NSFont.systemFont(ofSize: 13.0)

        textField.delegate = context.coordinator

        textField.isBezeled = true
        textField.isEditable = true

        return textField
    }

    //   Reads value from binding, formats as "%.0f",
    //   sets stringValue on the NSTextField
    func updateNSView(_ nsView: NSTextField, context: Context) {
        let formatted = String(format: "%.0f", value)
        nsView.stringValue = formatted
    }
}
