// Settings of the Storage widget (2026-10-20). Key "storageWidgetSettings"
// (declared at the end of this file; pattern: SettingsUI/SettingsDecoding.swift).
import Foundation

enum StorageDisplayMode: String, Codable, CaseIterable, Hashable {
    /// "123 GB free" under each ring.
    case gigabytes
    /// "62% used" under each ring.
    case percent
}

struct StorageWidgetSettings: Preferences, WidgetPrefs, Codable, Equatable, Hashable {
    /// Volume IDs (StorageVolume.id) the user hid. A hide-list rather than a show-list, so a newly
    /// mounted volume appears without visiting the settings.
    var hiddenVolumeIDs: [String] = []
    var displayMode: StorageDisplayMode = .gigabytes
    /// Show mounted disk images (.dmg) as well as real disks.
    var showDiskImages: Bool = true

    static let `default` = StorageWidgetSettings()

    var gridSizeType: NookWidget.NookGridSizeType { .small }   // width: NookWidgetLayout (4 cells)

    init() {}

    // Tolerant decoding: a missing or undecodable field keeps its default.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.decodeSetting(.hiddenVolumeIDs, into: &hiddenVolumeIDs)
        c.decodeSetting(.displayMode, into: &displayMode)
        c.decodeSetting(.showDiskImages, into: &showDiskImages)
    }

    private enum CodingKeys: String, CodingKey {
        case hiddenVolumeIDs, displayMode, showDiskImages
    }

    /// The volumes the widget shows, in the manager's order.
    func visible(_ volumes: [StorageVolume]) -> [StorageVolume] {
        volumes.filter { v in
            if hiddenVolumeIDs.contains(v.id) { return false }
            if v.kind == .diskImage && !showDiskImages { return false }
            return true
        }
    }
}

extension SettingKey {
    static let storageWidgetSettings = "storageWidgetSettings"
}

extension StoredKeys {
    static let storageWidgetSettings = Key<StorageWidgetSettings>(SettingKey.storageWidgetSettings, default: .default)
}
