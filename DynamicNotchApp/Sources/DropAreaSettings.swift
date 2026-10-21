import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

// Drop Area settings (Settings ▸ Nook ▸ Drop Area). The legacy CodingKeys (enabled / autoImport /
//   monitoredFolder / fileTypes / maxFileSize) have no use site and are kept for compatibility
//   with stored values, next to the options the drop area implements. Decoding is tolerant (decodeIfPresent).
struct DropAreaSettings: Preferences, Decodable, Encodable, Equatable, Hashable {
    /// open the notch (drop targets) when files are dragged over / near it
    var enabled: Bool = true
    /// show the AirDrop drop target next to the Tray target
    var showAirDropTarget: Bool = true

    // legacy keys (unused)
    var autoImport: Bool = false
    var monitoredFolder: String = ""
    var fileTypes: [String] = []
    var maxFileSize: Int = 0

    enum CodingKeys: String, CodingKey {
        case enabled, showAirDropTarget, autoImport, monitoredFolder, fileTypes, maxFileSize
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DropAreaSettings()
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? d.enabled
        showAirDropTarget = (try? c.decodeIfPresent(Bool.self, forKey: .showAirDropTarget)) ?? d.showAirDropTarget
        autoImport = (try? c.decodeIfPresent(Bool.self, forKey: .autoImport)) ?? d.autoImport
        monitoredFolder = (try? c.decodeIfPresent(String.self, forKey: .monitoredFolder)) ?? d.monitoredFolder
        fileTypes = (try? c.decodeIfPresent([String].self, forKey: .fileTypes)) ?? d.fileTypes
        maxFileSize = (try? c.decodeIfPresent(Int.self, forKey: .maxFileSize)) ?? d.maxFileSize
    }
}
