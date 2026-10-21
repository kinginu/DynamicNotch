import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

struct LiquidBasicSettings: Preferences, Decodable, Encodable, Equatable, Hashable {
    // Basic Liquid Glass sliders. The stored keys (field08 … field78) are kept as they are so
    //   saved settings keep decoding; all are 0…1 sliders except field78 (a multiplier) and
    //   field58 (a threshold).
    var field08: Double = 0.5
    var field10: Double = 0.5
    var field18: Double = 0.5
    var field20: Double = 0.5
    var field28: Double = 0.5
    var field30: Double = 0.5
    var field38: Double = 0.5
    var field40: Bool = true
    var field58: Double = 0.0
    var field78: Double = 1.0

    var derived: LiquidGlassSettings {
        // NativeGlassParams models blur and intensity; both follow field08 linearly
        var settings = LiquidGlassSettings()
        settings.params.bluRadius = CGFloat(field08 * 20.0)
        settings.params.intensity = CGFloat(field08 * 0.6 + 0.4)
        return settings
    }

}
