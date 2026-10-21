import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// Effect on the trailing side of the media live activity; settings view tests tag 3 == .customGIF
enum MediaLiveActivityEffectEnum: String, CaseIterable, Codable, Equatable, Hashable, Identifiable, CustomStringConvertible {
    case none
    case visualizer
    case albumArt
    case customGIF

    var id: String { rawValue }

    var description: String {
        switch self {
        case .none: return String(localized: "None")
        case .visualizer: return String(localized: "Visualizer")
        case .albumArt: return String(localized: "Album Art")
        case .customGIF: return String(localized: "Custom GIF")
        }
    }
}
