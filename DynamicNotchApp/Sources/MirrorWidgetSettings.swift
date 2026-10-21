// Settings of the Mirror (camera) widget. Key "mirrorWidgetSettings" (typed key
// still in Support/Ext-C.swift; pattern: SettingsUI/SettingsDecoding.swift). The chosen camera and
// the mirroring switch are separate keys (`defaultMirrorDevice`, `mirrorCameraInputWhenAvail`,
// Support/Ext-D.swift).
import Foundation

struct MirrorWidgetSettings: Preferences, WidgetPrefs, Codable, Equatable, Hashable {
    // NotchView reads `.disabled` / `.gridPoint` on every widget settings value.
    var disabled: Bool = false
    var gridPoint: NookGrid.Point = NookGrid.Point(value: 0)
    /// Stored grid size (the displayed width follows the camera's aspect).
    var gridSize: NookGrid.Size = NookGrid.Size(width: .init(value: 1), height: .init(value: 1))
    /// Camera quality (unused).
    var highQuality: Bool = false
    /// Show a frame around the preview.
    var showFrame: Bool = true
    /// Start the camera when the Nook opens.
    var autoOpen: Bool = false

    private enum CodingKeys: String, CodingKey {
        case disabled, gridPoint, gridSize, highQuality, showFrame, autoOpen
    }

    static let `default` = MirrorWidgetSettings()

    var gridSizeType: NookWidget.NookGridSizeType { NookWidget.mirror.gridSizeType }
}

extension MirrorWidgetSettings {
    // Tolerant decoding: a missing or undecodable field keeps its default.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.decodeSetting(.disabled, into: &disabled)
        c.decodeSetting(.gridPoint, into: &gridPoint)
        c.decodeSetting(.gridSize, into: &gridSize)
        c.decodeSetting(.highQuality, into: &highQuality)
        c.decodeSetting(.showFrame, into: &showFrame)
        c.decodeSetting(.autoOpen, into: &autoOpen)
    }
}
