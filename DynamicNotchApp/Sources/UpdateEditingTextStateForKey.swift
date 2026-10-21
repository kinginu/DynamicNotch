import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
struct UpdateEditingTextStateForKey: EnvironmentKey {
    static let defaultValue: (NSWindow?, Bool) -> Void = { _, _ in }
}
