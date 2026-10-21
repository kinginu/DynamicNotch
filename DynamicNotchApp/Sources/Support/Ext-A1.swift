// Notch open / close helpers: the spring animations of the notch footprint and indicators, the
// `vibrate()` haptic helper, and the shared ActiveLiveActivitiesManager instance.
import AppKit
import SwiftUI

// MARK: - Animations referenced by the notch open/close/indicator code

extension Animation {
    /// Open / close footprint springs used when Liquid Glass is enabled.
    static var liquidOpenFootprint: Animation { .spring(response: 0.42, dampingFraction: 0.78, blendDuration: 0) }
    static var liquidCloseFootprint: Animation { .spring(response: 0.38, dampingFraction: 0.9, blendDuration: 0) }
    static var liquidHoverOut: Animation { .spring(response: 0.3, dampingFraction: 0.85, blendDuration: 0) }
    /// Non-glass open animation.
    static var defaultTransition: Animation { .spring(response: 0.4, dampingFraction: 0.8, blendDuration: 0) }
    /// Volume / brightness indicator resize animation.
    static var indicatorResize: Animation { .spring(response: 0.3, dampingFraction: 0.8, blendDuration: 0) }
}

// MARK: - Haptics

/// A generic trackpad haptic, when Settings ▸ General ▸ Haptic feedback is on.
func vibrate() {
    guard SettingsStore[.generalSettings].hapticFeedbackEnabled else { return }
    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
}

// MARK: - Singletons used by NotchView

extension ActiveLiveActivitiesManager {
    /// The app's live-activity list (ActiveLiveActivitiesManager.swift defers this declaration here).
    static let shared = ActiveLiveActivitiesManager()
}
