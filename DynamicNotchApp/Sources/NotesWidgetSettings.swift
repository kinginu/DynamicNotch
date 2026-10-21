// Settings of the Notes widget. Key "notesWidgetSettings" (typed key still in
// Support/Ext-C.swift; pattern: SettingsUI/SettingsDecoding.swift).
import Foundation

struct NotesWidgetSettings: Preferences, WidgetPrefs, Codable, Equatable, Hashable {
    // NotchView reads `.disabled` / `.gridPoint` on every widget settings value.
    var disabled: Bool = false
    var gridPoint: NookGrid.Point = NookGrid.Point(value: 0)
    /// Stored grid size (kept for stored-value compatibility).
    var gridSize: NookGrid.Size = NookGrid.Size(width: .init(value: 1), height: .init(value: 1))
    /// Show the note title.
    var showTitle: Bool = true
    /// Show the date of each note.
    var showDate: Bool = false
    /// Language of code notes. Was CodeEditor.Language (stored as its raw string); code notes have
    /// no highlighting since CodeEditor/Highlightr were dropped (2026-10-20), so this is unused.
    var codeEditorLanguage: String = "plaintext"
    /// Show a preview of each note's text.
    var showPreview: Bool = false

    private enum CodingKeys: String, CodingKey {
        case disabled, gridPoint, gridSize, showTitle, showDate, codeEditorLanguage, showPreview
    }

    static let `default` = NotesWidgetSettings()

    var gridSizeType: NookWidget.NookGridSizeType { NookWidget.notes.gridSizeType }
}

extension NotesWidgetSettings {
    // Tolerant decoding: a missing or undecodable field keeps its default.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.decodeSetting(.disabled, into: &disabled)
        c.decodeSetting(.gridPoint, into: &gridPoint)
        c.decodeSetting(.gridSize, into: &gridSize)
        c.decodeSetting(.showTitle, into: &showTitle)
        c.decodeSetting(.showDate, into: &showDate)
        c.decodeSetting(.codeEditorLanguage, into: &codeEditorLanguage)
        c.decodeSetting(.showPreview, into: &showPreview)
    }
}
