import UniformTypeIdentifiers
import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// ConditionalContent(NoteCodeEditor / RichTextEditor)
// fileExporter, toolBar, @State editMode
// NoteDocument via Observation + SwiftData, .frame(780, 800)
struct ExpandedNoteView: View {

    @State private var editMode: Bool = false

    @Environment(\.noteDocument) private var noteDoc: NoteDocument?
    // the edited note comes from ExpandedNoteManager.activeNote
    @Environment(\.expandedNoteManager) private var expandedNoteManager
    @State private var isExporting: Bool = false

    var body: some View {
        // ConditionalContent: NoteCodeEditor or NoteRichEditor (CRichTextEditor)
        // depending on the note's mode; RichTextEditor(document:) / .toolBar did not exist.
        Group {
            if let note = expandedNoteManager?.activeNote {
                if note.isCodeMode {
                    NoteCodeEditor(note: note)
                } else {
                    NoteRichEditor(note: note)
                }
            } else {
                Color.clear
            }
        }
        .fileExporter(isPresented: $isExporting, document: noteDoc ?? NoteDocument(), contentType: .rtf) { _ in }
        .toolbar {

            Button(action: { editMode.toggle() }) {
                Image(systemName: editMode ? "pencil.slash" : "pencil")
            }
        }
        .frame(width: 780, height: 800)
    }
}
