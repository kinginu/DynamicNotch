// Settings of the Clipboard history widget (UI requirement (4), 2026-10-20).
//
// Key "clipboardWidgetSettings" (typed key still in Support/Ext-C.swift; pattern: SettingsUI/SettingsDecoding.swift). The history itself is
// not stored here but in Application Support (ClipboardHistoryManager).
import Foundation

struct ClipboardWidgetSettings: Preferences, WidgetPrefs, Codable, Equatable, Hashable {
    /// Record new clipboard contents (the widget can stay in the Nook while recording is paused).
    var isRecording: Bool = true
    /// Maximum number of history items kept (oldest are dropped).
    var historyLimit: Int = 50
    /// Record copied images (stored as PNG next to the history, ≤ `ClipboardHistoryManager.maxImageBytes`).
    var captureImages: Bool = true
    /// Record copied files (Finder ⌘C) as file references.
    var captureFiles: Bool = true
    /// Bundle identifiers of apps whose copies are never recorded.
    var excludedBundleIDs: [String] = []

    /// Choices offered for `historyLimit` in the settings.
    static let historyLimitChoices = [10, 25, 50, 100, 200]

    static let `default` = ClipboardWidgetSettings()

    var gridSizeType: NookWidget.NookGridSizeType { NookWidget.clipboard.gridSizeType }

    init() {}

    // Tolerant decoding: a missing or undecodable field keeps its default.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.decodeSetting(.isRecording, into: &isRecording)
        c.decodeSetting(.historyLimit, into: &historyLimit)
        c.decodeSetting(.captureImages, into: &captureImages)
        c.decodeSetting(.captureFiles, into: &captureFiles)
        c.decodeSetting(.excludedBundleIDs, into: &excludedBundleIDs)
    }

    private enum CodingKeys: String, CodingKey {
        case isRecording, historyLimit, captureImages, captureFiles, excludedBundleIDs
    }
}
