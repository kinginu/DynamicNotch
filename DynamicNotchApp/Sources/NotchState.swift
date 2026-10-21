import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
enum NotchState: Equatable, Hashable {
    // Display states of the notch; NotchViewModel sets .inline (tag 2) and .full (tag 4)
    // through `init(unsafeTag:)`.
    case hidden
    case nook
    case inline
    case locked
    case full
}
