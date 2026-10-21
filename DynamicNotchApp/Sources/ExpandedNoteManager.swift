// ExpandedNoteManager — state of the expanded note editor in the notch (`\.expandedNoteState`,
// created by RootView): the note being edited, whether the editor is expanded, where its window
// sits, the formatting state of its rich-text editor, and the on-screen origins of the note
// buttons it expands from.
import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
final class ExpandedNoteManager {
    /// The note shown in the expanded editor.
    var activeNote: Note?
    var isExpanded = false
    /// Origin of the expanded editor window, once it has been placed.
    var windowOrigin: CGPoint?
    /// Formatting state of the expanded editor (bold / italic / … at the selection).
    var richTextContext = NoteTextFormatting()
    /// On-screen origin of each note button, keyed by note id (the expand animation starts there).
    var buttonsOrigins: [String: CGPoint] = [:]
    /// Opens a note in a window: (note, window id, focus).
    var openWindow: ((Note, UUID, Bool) -> Void)?

    init() {}

    func setButtonOrigin(of key: String, to point: CGPoint) {
        buttonsOrigins[key] = point
    }
}
