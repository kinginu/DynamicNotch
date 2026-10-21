// Settings of the Bluetooth widget (2026-10-20). Key "bluetoothWidgetSettings"
// (declared at the end of this file; pattern: SettingsUI/SettingsDecoding.swift).
import Foundation

struct BluetoothWidgetSettings: Preferences, WidgetPrefs, Codable, Equatable, Hashable {
    /// Show only the devices marked as favourites (right-click in the widget, or Settings).
    var showOnlyFavourites: Bool = false
    /// Hide paired devices without a name (only their Bluetooth address is known).
    var hideUnnamed: Bool = true
    /// Favourite devices by normalized Bluetooth address ("aa:bb:cc:dd:ee:ff").
    var favourites: [String] = []

    static let `default` = BluetoothWidgetSettings()

    var gridSizeType: NookWidget.NookGridSizeType { .small }

    init() {}

    // Tolerant decoding: a missing or undecodable field keeps its default.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.decodeSetting(.showOnlyFavourites, into: &showOnlyFavourites)
        c.decodeSetting(.hideUnnamed, into: &hideUnnamed)
        c.decodeSetting(.favourites, into: &favourites)
    }

    private enum CodingKeys: String, CodingKey {
        case showOnlyFavourites, hideUnnamed, favourites
    }

    func isFavourite(_ id: String) -> Bool { favourites.contains(id) }

    mutating func toggleFavourite(_ id: String) {
        if let i = favourites.firstIndex(of: id) { favourites.remove(at: i) } else { favourites.append(id) }
    }

    /// The devices the widget shows: filtered by the settings, connected first, then favourites,
    /// then by name.
    func visible(_ devices: [BluetoothWidgetDevice]) -> [BluetoothWidgetDevice] {
        devices
            .filter { !(hideUnnamed && $0.isUnnamed) && (!showOnlyFavourites || isFavourite($0.id)) }
            .sorted { a, b in
                if a.isConnected != b.isConnected { return a.isConnected }
                let fa = isFavourite(a.id), fb = isFavourite(b.id)
                if fa != fb { return fa }
                return a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending
            }
    }
}

extension SettingKey {
    static let bluetoothWidgetSettings = "bluetoothWidgetSettings"
}

extension StoredKeys {
    static let bluetoothWidgetSettings = Key<BluetoothWidgetSettings>(SettingKey.bluetoothWidgetSettings, default: .default)
}
