import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// Behaviour of the notch while an app is fullscreen. Currently unused.
enum FullscreenOption: String, Codable, Equatable, Hashable, CaseIterable {
    case show
    case hide
    case hideOnlyOnNotchScreen
}
