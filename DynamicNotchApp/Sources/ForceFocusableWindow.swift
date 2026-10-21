import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
import AppKit

class ForceFocusableWindow: NSWindow {
    var firstResponderChanged: ((NSResponder?) -> Void)?

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let result = super.makeFirstResponder(responder)

        if responder == nil {
            if !result {
                firstResponderChanged?(nil)
            }
        } else {
            if let textView = responder as? NSTextView, textView.hasMarkedText() {
                // skip while editing marked text (IME composition)
                return result
            }
            if result {
                firstResponderChanged?(responder)
            }
        }
        return result
    }

    override func sendEvent(_ event: NSEvent) {
        super.sendEvent(event)

        guard event.type == .leftMouseDown else { return }

        guard let firstResponder = self.firstResponder else { return }

        guard let view = firstResponder as? NSView else { return }

        let isEditableText: Bool
        if let textView = view as? NSTextView {
            isEditableText = textView.isEditable
        } else if let textField = view as? NSTextField {
            isEditableText = textField.isEditable
        } else {
            return
        }

        if isEditableText {
            let visibleRect = view.visibleRect
            let clickPoint = event.locationInWindow
            let convertedPoint = view.convert(clickPoint, from: nil)

            if NSPointInRect(convertedPoint, visibleRect) {
                NSApp.activate(ignoringOtherApps: true)
                self.makeKeyAndOrderFront(nil)
            }
        }
    }
}
