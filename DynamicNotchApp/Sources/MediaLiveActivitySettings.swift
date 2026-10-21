import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
import Foundation

// MARK: - MediaLiveActivitySettings

// Settings for media live activity appearance (album art, GIF, effect)
struct MediaLiveActivitySettings: Preferences, Decodable, Encodable, Equatable, Hashable {

    // MARK: - Stored properties

    // defaults so `init()` (Preferences) exists
    var isAutomaticallyColored: Bool = true

    var albumCornerRadius: Double = 6

    var effect: MediaLiveActivityEffectEnum = .visualizer

    var gifVerticalOffset: Double = 0

    var gifHorizontalOffset: Double = 0

    var customGifURL: URL? = nil

    var gifScale: Double = 1

    var gifScalingQuality: GIFScalingQuality = .high

    init() {}

    // MARK: - Codable

    // Creates keyed container with CodingKeys, decodes 8 properties
    // tolerant: missing keys fall back to defaults
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Decode each field in order (tags 0-7)
        isAutomaticallyColored = try container.decodeIfPresent(Bool.self, forKey: .isAutomaticallyColored) ?? Self.fallback.isAutomaticallyColored
        albumCornerRadius = try container.decodeIfPresent(Double.self, forKey: .albumCornerRadius) ?? Self.fallback.albumCornerRadius
        effect = try container.decodeIfPresent(MediaLiveActivityEffectEnum.self, forKey: .effect) ?? Self.fallback.effect
        gifVerticalOffset = try container.decodeIfPresent(Double.self, forKey: .gifVerticalOffset) ?? Self.fallback.gifVerticalOffset
        gifHorizontalOffset = try container.decodeIfPresent(Double.self, forKey: .gifHorizontalOffset) ?? Self.fallback.gifHorizontalOffset
        customGifURL = try container.decodeIfPresent(URL.self, forKey: .customGifURL)
        gifScale = try container.decodeIfPresent(Double.self, forKey: .gifScale) ?? Self.fallback.gifScale
        gifScalingQuality = try container.decodeIfPresent(GIFScalingQuality.self, forKey: .gifScalingQuality) ?? Self.fallback.gifScalingQuality
    }

    private static let fallback = MediaLiveActivitySettings()

    // Equatable consistent with the hand-written hash
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isAutomaticallyColored == rhs.isAutomaticallyColored && lhs.albumCornerRadius == rhs.albumCornerRadius &&
        lhs.effect == rhs.effect && lhs.gifVerticalOffset == rhs.gifVerticalOffset &&
        lhs.gifHorizontalOffset == rhs.gifHorizontalOffset && lhs.customGifURL == rhs.customGifURL &&
        lhs.gifScale == rhs.gifScale && lhs.gifScalingQuality == rhs.gifScalingQuality
    }

    // encode(to:)
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isAutomaticallyColored, forKey: .isAutomaticallyColored)
        try container.encode(albumCornerRadius, forKey: .albumCornerRadius)
        try container.encode(effect, forKey: .effect)
        try container.encode(gifVerticalOffset, forKey: .gifVerticalOffset)
        try container.encode(gifHorizontalOffset, forKey: .gifHorizontalOffset)
        try container.encodeIfPresent(customGifURL, forKey: .customGifURL)
        try container.encode(gifScale, forKey: .gifScale)
        try container.encode(gifScalingQuality, forKey: .gifScalingQuality)
    }

    // hash(into:)
    func hash(into hasher: inout Hasher) {
        hasher.combine(isAutomaticallyColored)
        hasher.combine(albumCornerRadius)
        hasher.combine(effect)
        hasher.combine(gifVerticalOffset)
        hasher.combine(gifHorizontalOffset)
        hasher.combine(customGifURL)
        hasher.combine(gifScale)
        hasher.combine(gifScalingQuality)
    }

    // MARK: - CodingKeys

    // Case 0: "isAutomaticallyColored" (d000000000000016 = length 22, pointer to string)
    // Case 1: "albumCornerRadius" (length 17)
    // Case 3: "gifVerticalOffset" (length 19: d000000000000013)
    // Case 4: "gifHorizontalOffset" (length 19)
    // Case 7: "gifScalingQuality" (length 17)
    // Case 8 "selectedGIF" (a predefined bundled GIF) was removed 2026-10-20 with the bundled GIFs;
    //   a stored value is ignored on decode.
    enum CodingKeys: String, CodingKey, CaseIterable, Equatable, Hashable, CustomStringConvertible, CustomDebugStringConvertible {
        case isAutomaticallyColored
        case albumCornerRadius
        case effect
        case gifVerticalOffset
        case gifHorizontalOffset
        case customGifURL
        case gifScale
        case gifScalingQuality

        // String-backed CodingKey via enum raw value
        var stringValue: String {
            return rawValue
        }
    }
}

// MARK: - Support enums

// MediaLiveActivityEffectEnum is declared in MediaLiveActivityEffectEnum.swift

// GIF scaling quality
enum GIFScalingQuality: String, Codable, Equatable, Hashable, CaseIterable {
    case low
    case medium
    case high
}
