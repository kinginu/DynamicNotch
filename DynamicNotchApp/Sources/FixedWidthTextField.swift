import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
import SwiftUI
import Foundation

struct FixedWidthTextField: NSViewRepresentable {
    @Binding var text: String

    var placeholder: String

    var isSecure: Bool = false

    @Binding var width: Double

    func makeNSView(context: NSViewRepresentableContext<FixedWidthTextField>) -> NSTextField {
        let textField: NSTextField
        if isSecure {
            textField = NSSecureTextField(frame: .zero)
        } else {
            textField = NSTextField(frame: .zero)
        }

        textField.placeholderString = placeholder

        textField.delegate = context.coordinator

        textField.cell?.wraps = false
        textField.cell?.isScrollable = true

        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: NSViewRepresentableContext<FixedWidthTextField>) {
        nsView.stringValue = text
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FixedWidthTextField

        init(parent: FixedWidthTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else {
                return
            }

            let stringValue = textField.stringValue

            var filtered = ""
            for char in stringValue {
                if !char.isWhitespace {
                    filtered.append(char)
                }
            }

            parent.text = filtered

            parent.width = Double(filtered.count) * 8.0  // approximate character width
        }
    }
}
