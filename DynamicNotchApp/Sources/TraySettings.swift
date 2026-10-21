import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import Foundation

// Settings for the Files Tray. The legacy keys (trayPosition / autoHide / autoHideDelay / iconSize)
//   have no use site and are kept for stored-value compatibility; the other options are the ones
//   the tray implements. Decoding is tolerant (decodeIfPresent), so a
//   value stored by an older build keeps working.
struct TraySettings: Preferences, Decodable, Encodable, Equatable, Hashable {

    // legacy keys (unused by the UI)
    var trayPosition: TrayPosition = .rightEdge
    var autoHide: Bool = true
    var autoHideDelay: Double = 3.0
    var iconSize: CGFloat = 32.0

    // show file names under the tray icons
    var showLabels: Bool = true

    // true: dropped files are copied into the tray folder (Tray.addFilesFromURLs copies);
    //   false: the tray keeps a reference to the original file.
    var copyFiles: Bool = true

    // keep the tray's files across relaunches (Tray.persist/loadPersistedFiles)
    var keepFilesAfterQuit: Bool = true

    // remove a file from the tray once it has been dragged out to another app
    var removeAfterDraggingOut: Bool = false

    // show the "Files Tray" live activity beside the notch while the tray has files
    var showLiveActivity: Bool = true

    // MARK: - TrayPosition

    enum TrayPosition: String, Codable, Equatable, Hashable {
        case rightEdge = "rightEdge"
        case leftEdge = "leftEdge"
    }

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case trayPosition, autoHide, autoHideDelay, iconSize, showLabels
        case copyFiles, keepFilesAfterQuit, removeAfterDraggingOut, showLiveActivity
    }

    init() {}

    // tolerant decoding: missing keys fall back to the defaults
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TraySettings()
        trayPosition = (try? c.decodeIfPresent(TrayPosition.self, forKey: .trayPosition)) ?? d.trayPosition
        autoHide = (try? c.decodeIfPresent(Bool.self, forKey: .autoHide)) ?? d.autoHide
        autoHideDelay = (try? c.decodeIfPresent(Double.self, forKey: .autoHideDelay)) ?? d.autoHideDelay
        iconSize = (try? c.decodeIfPresent(CGFloat.self, forKey: .iconSize)) ?? d.iconSize
        showLabels = (try? c.decodeIfPresent(Bool.self, forKey: .showLabels)) ?? d.showLabels
        copyFiles = (try? c.decodeIfPresent(Bool.self, forKey: .copyFiles)) ?? d.copyFiles
        keepFilesAfterQuit = (try? c.decodeIfPresent(Bool.self, forKey: .keepFilesAfterQuit)) ?? d.keepFilesAfterQuit
        removeAfterDraggingOut = (try? c.decodeIfPresent(Bool.self, forKey: .removeAfterDraggingOut)) ?? d.removeAfterDraggingOut
        showLiveActivity = (try? c.decodeIfPresent(Bool.self, forKey: .showLiveActivity)) ?? d.showLiveActivity
    }
}
