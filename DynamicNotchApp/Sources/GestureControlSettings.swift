import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
import Foundation

struct GestureControlSettings: Preferences, Codable, Equatable, Hashable {
    var allowGestures: Bool = true
    var controlMedia: Bool = true
    var controlOpenState: Bool = true
    var invertMediaGestures: Bool = false

    // Preferences requires init(); defaults are the property initialisers
    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        allowGestures = try container.decodeIfPresent(Bool.self, forKey: .allowGestures) ?? true
        controlMedia = try container.decodeIfPresent(Bool.self, forKey: .controlMedia) ?? true
        controlOpenState = try container.decodeIfPresent(Bool.self, forKey: .controlOpenState) ?? true
        invertMediaGestures = try container.decodeIfPresent(Bool.self, forKey: .invertMediaGestures) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(allowGestures, forKey: .allowGestures)
        try container.encode(controlMedia, forKey: .controlMedia)
        try container.encode(controlOpenState, forKey: .controlOpenState)
        try container.encode(invertMediaGestures, forKey: .invertMediaGestures)
    }

    enum CodingKeys: String, CodingKey, CustomStringConvertible, CustomDebugStringConvertible, Equatable, Hashable {
        case allowGestures
        case controlMedia
        case controlOpenState
        case invertMediaGestures
    }
}
