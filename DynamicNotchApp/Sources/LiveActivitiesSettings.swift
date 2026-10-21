import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import Foundation

// Settings for live activities display behavior
struct LiveActivitiesSettings: Preferences, Decodable, Encodable, Equatable, Hashable {

    // Whether live activities are enabled
    var enabled: Bool = true

    // Maximum number of displayed activities
    var maxDisplayCount: Int = 5

    // Animation style for transitions
    var animationStyle: String = "slide"

    // Auto-hide delay in seconds
    var autoHideDuration: Double = 3.0

    // members referenced by NotchView / TopBarContentView / DynamicNotchState
    var enableVolumeBrightness: Bool = true
    /// Raw values (`LiveActivity.rawValue`) of activities the user switched off.
    var disabledActivities: Set<String> = []

    // current persisted value (call sites use `LiveActivitiesSettings.shared`)
    static var shared: LiveActivitiesSettings { SettingsStore[.liveActivitiesSettings] }
    static var disabledActivityIdentifiers: Set<String> { shared.disabledActivities }

    // MARK: - CodingKeys

    // CodingKeys enum with String raw values

    // MARK: - Encodable

    // Standard encodable synthesis

    // MARK: - Hashable

    // Standard hash combination
}