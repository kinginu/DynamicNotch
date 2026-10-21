import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// Backs `EnvironmentValues.inMemoryGeneralSettings`. Holds a cached copy of GeneralSettings, refreshed from SettingsStore.
class InMemoryDefault {
    var value: GeneralSettings

    init(value: GeneralSettings = SettingsStore[.generalSettings]) {
        self.value = value
    }

    func reload() {
        value = SettingsStore[.generalSettings]
    }

    var hapticEnabled: Bool { value.hapticFeedbackEnabled }
}
