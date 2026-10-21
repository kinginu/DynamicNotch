import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
struct ResignFirstResponderKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}
