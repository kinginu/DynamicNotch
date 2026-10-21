import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
struct CloseNotchKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}
