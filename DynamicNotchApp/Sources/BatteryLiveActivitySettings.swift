import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import Foundation

// Settings for battery live activity with Codable/Hashable conformance
struct BatteryLiveActivitySettings: Preferences, Decodable, Encodable, Equatable, Hashable {

    // Whether battery live activity is enabled
    var enabled: Bool = true

    // Show battery percentage in activity
    var showPercentage: Bool = true

    // Show charging status in activity
    var showChargingStatus: Bool = true

    // Low power mode alert
    var lowPowerAlert: Bool = true

    // Auto-hide when battery is full
    var autoHideWhenFull: Bool = false

    // MARK: - CodingKeys

    // Coding keys for Codable conformance

    // MARK: - hashValue

    // Hasher-based hash combining all fields

    // MARK: - encode

    // encode(to: Encoder) throws
    // Encodes all 5 fields using keyed container
}