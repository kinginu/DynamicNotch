import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// Non-editable NSTextField label whose
//   paragraph style disables hyphenation (SwiftUI Text may hyphenate in some locales).
struct NonHyphenatingText: NSViewRepresentable {
    var text: String
    var font: NSFont = .systemFont(ofSize: NSFont.systemFontSize)
    var color: NSColor = .labelColor
    var alignment: NSTextAlignment = .natural

    init(_ text: String, font: NSFont = .systemFont(ofSize: NSFont.systemFontSize),
         color: NSColor = .labelColor, alignment: NSTextAlignment = .natural) {
        self.text = text
        self.font = font
        self.color = color
        self.alignment = alignment
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.lineBreakMode = .byWordWrapping
        field.maximumNumberOfLines = 0
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        update(field)
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        update(nsView)
    }

    private func update(_ field: NSTextField) {
        let style = NSMutableParagraphStyle()
        style.hyphenationFactor = 0
        style.alignment = alignment
        style.lineBreakMode = .byWordWrapping
        field.attributedStringValue = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: style,
        ])
    }
}
