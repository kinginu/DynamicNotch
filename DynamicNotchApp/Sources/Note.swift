// Note — the SwiftData model of a Notes-widget note (rich text, or code with a language), stored
// in the app's model container (NookModelContainer). `richText` is persisted through
// NSAttributedStringTransformer (`@Attribute(.transformable(by:))`).
//
// DN_CLT_HARNESS: the Command Line Tools harness (Package.swift) has no SwiftDataMacros plugin, so
// it type-checks against a hand-written PersistentModel conformance instead of `@Model`.
import Foundation
import Observation
import SwiftData

#if DN_CLT_HARNESS
@Observable
final class Note {
    var richText: NSAttributedString = NSAttributedString(string: "")
    var codeText: String = ""
    var codeLanguage: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var icon: String = "doc.text"
    var scrollPos: Double = 0.0
    var isCodeMode: Bool = false

    @ObservationIgnored var persistentBackingData: any BackingData<Note>

    init() {
        self.persistentBackingData = Note.createBackingData()
    }

    required init(backingData: any BackingData<Note>) {
        self.persistentBackingData = backingData
    }

    static var schemaMetadata: [Schema.PropertyMetadata] { [] }
}
extension Note: PersistentModel {}
#else
@Model
final class Note {
    @Attribute(.transformable(by: NSAttributedStringTransformer.self))
    var richText: NSAttributedString = NSAttributedString(string: "")
    var codeText: String = ""
    var codeLanguage: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var icon: String = "doc.text"
    var scrollPos: Double = 0.0
    var isCodeMode: Bool = false

    init() {}
}
#endif

extension Note {
    /// Plain-text title: the first line of the note.
    var title: String {
        let s = isCodeMode ? codeText : richText.string
        return s.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
    }

    /// The note as plain text.
    var text: String { isCodeMode ? codeText : richText.string }

    /// Sort key for `@Query(sort: \Note.modificationDate)` (alias of `updatedAt`).
    var modificationDate: Date { updatedAt }
}
