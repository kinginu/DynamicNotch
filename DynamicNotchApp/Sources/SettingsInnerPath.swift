import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
import Observation

@Observable
class SettingsInnerPath {

    var _tabIndex: Int? = 0

    var tabIndex: Int? {
        get {
            access(keyPath: \._tabIndex)
            return _tabIndex
        }
        set {
            // Equality check before withMutation to avoid unnecessary notifications
            guard _tabIndex != newValue else { return }
            withMutation(keyPath: \._tabIndex) {
                _tabIndex = newValue
            }
        }
    }

    static let shared = SettingsInnerPath()
}
