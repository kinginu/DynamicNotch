import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
struct GetNowKey: EnvironmentKey {
    static let defaultValue: () -> Date = { Date() }
}
