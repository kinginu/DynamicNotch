// NoteDocument — a note's rich text as a SwiftUI `FileDocument`, used to export a note as RTF
// (ExpandedNoteView's file exporter) and to pass a note through the environment (`\.noteDocument`).
// Reads RTF, RTFD and UTF-8 plain text; writes RTF.
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NoteDocument: FileDocument, @unchecked Sendable {
    // @unchecked Sendable: `FileDocument` requires Sendable and NSAttributedString is not marked
    // Sendable. The document only ever holds an immutable copy (see `richText`), which is safe to
    // share between threads.

    /// The note's content (stored as an immutable copy).
    var richText: NSAttributedString {
        get { storage }
        set { storage = NSAttributedString(attributedString: newValue) }
    }
    private var storage = NSAttributedString()

    var id: String = UUID().uuidString
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    // MARK: FileDocument

    static var readableContentTypes: [UTType] { [.rtf, .rtfd, .plainText] }
    static var writableContentTypes: [UTType] { [.rtf, .rtfd] }

    init() {}

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if configuration.contentType == .plainText {
            guard let string = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
            richText = NSAttributedString(string: string)
        } else {
            richText = try NSAttributedString(data: data, options: [:], documentAttributes: nil)
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let range = NSRange(location: 0, length: richText.length)
        let rtfData: Data
        do {
            rtfData = try richText.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        } catch {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSUnderlyingErrorKey: error])
        }
        let wrapper = FileWrapper(regularFileWithContents: rtfData)
        wrapper.preferredFilename = "\(id).rtf"
        return wrapper
    }
}
