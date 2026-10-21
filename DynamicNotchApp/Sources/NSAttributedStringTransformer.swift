// NSAttributedStringTransformer — stores `Note.richText` as RTF data in SwiftData
// (`@Attribute(.transformable(by:))`). Registered by NookModelContainer before the schema is built.
import AppKit
import Foundation
import os

private let logger = Logger(subsystem: "com.example.dynamicnotch.DynamicNotch", category: "notes")

final class NSAttributedStringTransformer: ValueTransformer {
    static let name = NSValueTransformerName("NSAttributedStringTransformer")

    // Must be the model value class: SwiftData / Core Data validate the attribute's value against
    // it. With NSData every write of Note.richText threw NSInvalidArgumentException ("desired type =
    // NSData; given type = NSConcreteAttributedString") and crashed the app.
    override class func transformedValueClass() -> AnyClass { NSAttributedString.self }
    override class func allowsReverseTransformation() -> Bool { true }

    /// NSAttributedString → RTF data.
    override func transformedValue(_ value: Any?) -> Any? {
        guard let input = value as? NSAttributedString else { return nil }
        do {
            return try input.data(from: NSRange(location: 0, length: input.length),
                                  documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        } catch {
            logger.error("note text could not be encoded as RTF: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// RTF data → NSAttributedString.
    override func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else { return nil }
        do {
            return try NSAttributedString(data: data, options: [.characterEncoding: String.Encoding.utf8.rawValue],
                                          documentAttributes: nil)
        } catch {
            logger.error("stored note text is not readable RTF: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
