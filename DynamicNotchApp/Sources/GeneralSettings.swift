import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import Foundation
import SwiftUI

// MARK: - GeneralSettings

// Similar pattern to LiquidBasicSettings — Defaults-backed Codable settings struct
struct GeneralSettings: Preferences, Decodable, Encodable, Equatable, Hashable {


    // Toggles overall animation on/off
    var animationEnabled: Bool = true

    // Time interval before auto-hiding the notch (in seconds)
    var autoHideNotchTime: CGFloat = 2.0

    // Whether to show changelog on version update. Unused since 2026-10-20 (no updater,
    //   no changelog window); kept so stored settings keep decoding unchanged.
    var showChangelog: Bool = true

    // Launch at login toggle
    var launchAtLogin: Bool = false

    // Enable/disable sound effects
    var soundFxEnabled: Bool = true

    var hapticFeedbackEnabled: Bool = true

    // Accessibility / permissions state (matching fullScreenMonitor references)
    var accessibilityGranted: Bool = false

    // members read by NotchView / NotchViewModel / widget views
    var liquidGlass: Bool = true
    var disabled: Bool = false
    var widgetWidth: CGFloat = 0
    var heightFineTuning: CGFloat = 0
    var isNonNotch: Bool = false
    var isNonNotchAndDisabled: Bool = false

    // alias used by NotchViewModel.hapticEnabled
    var hapticEnabled: Bool { hapticFeedbackEnabled }

    // instance + static spellings both appear at call sites
    var liquidGlassEnabled: Bool { liquidGlass }
    static var liquidGlassEnabled: Bool { SettingsStore[.generalSettings].liquidGlass }

    // MARK: - Encodable

    // Auto-synthesized compiler-generated encoder

    // MARK: - Hashable

    // Auto-synthesized from struct fields

    // MARK: - CodingKeys

    // Auto-synthesized CodingKey enum
}
