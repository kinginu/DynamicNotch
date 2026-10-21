// Settings of the Menu Bar widget (2026-10-20): hidden menu bar items shown inside the
// open notch. Key "menuBarItemsWidgetSettings"
// (declared at the end of this file; pattern: SettingsUI/SettingsDecoding.swift).
//
// Mechanism (MenuBarItemsManager.swift): our own separator status item; items to its left are
// pushed off the menu bar by giving the separator a very large length.
import Foundation

struct MenuBarItemsWidgetSettings: Preferences, WidgetPrefs, Codable, Equatable, Hashable {
    /// Put the separator in the menu bar and hide the items to its left (while the widget is in
    /// the Nook). Off: no separator, nothing hidden.
    var hidingEnabled: Bool = true
    /// Show the hidden items in the menu bar (separator shrunk to a chevron).
    var showHiddenItems: Bool = false
    /// Bundle identifiers of apps whose items should always stay in the menu bar. A hidden item of
    /// such an app is flagged in the widget/settings with a "Move to Menu Bar" action (⌘-drag).
    var alwaysShownBundleIDs: [String] = []
    /// Live images of the hidden items (Screen Recording). Off: names and app icons only.
    var showItemImages: Bool = true

    static let `default` = MenuBarItemsWidgetSettings()

    var gridSizeType: NookWidget.NookGridSizeType { .small }   // width: NookWidgetLayout.cells (5 = 250 pt)

    init() {}

    // Tolerant decoding: a missing or undecodable field keeps its default.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.decodeSetting(.hidingEnabled, into: &hidingEnabled)
        c.decodeSetting(.showHiddenItems, into: &showHiddenItems)
        c.decodeSetting(.alwaysShownBundleIDs, into: &alwaysShownBundleIDs)
        c.decodeSetting(.showItemImages, into: &showItemImages)
    }

    private enum CodingKeys: String, CodingKey {
        case hidingEnabled, showHiddenItems, alwaysShownBundleIDs, showItemImages
    }
}

extension SettingKey {
    static let menuBarItemsWidgetSettings = "menuBarItemsWidgetSettings"
}

extension StoredKeys {
    static let menuBarItemsWidgetSettings = Key<MenuBarItemsWidgetSettings>(SettingKey.menuBarItemsWidgetSettings, default: .default)
}
