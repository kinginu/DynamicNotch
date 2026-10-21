import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// One glass slab of NativeGlassPillView (frame, corner radius, opacity, rotation, shadow).
struct GlassSlab: Equatable {
    var rect: CGRect = .zero
    var cornerRadius: CGFloat = 0
    var opacity: Double = 1
    var rotation: CGFloat = 0
    var shadowOpacity: Double = 0
    var shadowOffset: CGSize = .zero
    var shadowRadius: CGFloat = 0
    var shadowColor: CGColor? = nil
}
