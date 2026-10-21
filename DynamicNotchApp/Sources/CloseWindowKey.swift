import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
struct CloseWindowKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}
