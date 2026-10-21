import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
struct EnableTextEditingForWindowWithKey: EnvironmentKey {
    static let defaultValue: (NSWindow?) -> Void = { _ in }
}
