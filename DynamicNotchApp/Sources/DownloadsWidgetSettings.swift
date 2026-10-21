// F8: settings of the Downloads widget (2026-10-20). Key: "downloadsWidgetSettings" (declared
// below; pattern: SettingsUI/SettingsDecoding.swift).
import Foundation

struct DownloadsWidgetSettings: Preferences, WidgetPrefs, Codable, Equatable, Hashable {
    /// Watched folder; nil = the user's Downloads folder.
    var folderPath: String? = nil
    /// Number of items the widget lists (newest first; more scroll).
    var itemCount: Int = 5
    /// List hidden files (dot files). They are never moved to the Trash by "Clear Old".
    var showHidden: Bool = false
    /// "Old" = added to the folder more than this many days ago (Clear Old, auto-clear).
    var clearAfterDays: Int = 30
    /// Move old items to the Trash automatically (opt-in, confirmed when turned on; at most every
    /// `DownloadsWatcher.autoClearInterval`).
    var autoClear: Bool = false
    /// Show a progress indicator in the closed notch while a download is in progress.
    var showInClosedNotch: Bool = true

    static let itemCountChoices = [3, 4, 5, 6, 8, 10]
    static let clearAfterChoices = [1, 7, 14, 30, 60, 90]

    static let `default` = DownloadsWidgetSettings()

    var gridSizeType: NookWidget.NookGridSizeType { NookWidget.downloads.gridSizeType }

    /// The watched folder (the Downloads folder unless one was chosen).
    var folderURL: URL {
        if let folderPath, !folderPath.isEmpty {
            return URL(fileURLWithPath: (folderPath as NSString).expandingTildeInPath, isDirectory: true)
        }
        return URL.downloadsDirectory
    }

    var usesDefaultFolder: Bool { folderPath?.isEmpty ?? true }

    init() {}

    // Tolerant decoding: a missing or undecodable field keeps its default.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.decodeSetting(.folderPath, into: &folderPath)
        c.decodeSetting(.itemCount, into: &itemCount)
        c.decodeSetting(.showHidden, into: &showHidden)
        c.decodeSetting(.clearAfterDays, into: &clearAfterDays)
        c.decodeSetting(.autoClear, into: &autoClear)
        c.decodeSetting(.showInClosedNotch, into: &showInClosedNotch)
    }

    private enum CodingKeys: String, CodingKey {
        case folderPath, itemCount, showHidden, clearAfterDays, autoClear, showInClosedNotch
    }
}

extension SettingKey {
    static let downloadsWidgetSettings = "downloadsWidgetSettings"
}

extension StoredKeys {
    static let downloadsWidgetSettings = Key<DownloadsWidgetSettings>(SettingKey.downloadsWidgetSettings, default: .default)
}
