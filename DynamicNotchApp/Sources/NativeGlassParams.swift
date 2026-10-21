import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// Glass parameters stored in LiquidGlassSettings (Codable/Hashable)
//   and produced by GlassAspect.Simple.resolved.
struct NativeGlassParams: Equatable, Hashable, Codable {
    var bluRadius: CGFloat = 12.0
    var intensity: CGFloat = 0.6
    var tint: GlassRGBA = GlassRGBA(red: 0, green: 0, blue: 0, alpha: 0)

    init() {}

    init(bluRadius: CGFloat, intensity: CGFloat, tintColor: Color) {
        self.bluRadius = bluRadius
        self.intensity = intensity
        // Color is not Codable; store sRGB components
        let ns = NSColor(tintColor).usingColorSpace(.sRGB) ?? .clear
        self.tint = GlassRGBA(red: Double(ns.redComponent), green: Double(ns.greenComponent),
                              blue: Double(ns.blueComponent), alpha: Double(ns.alphaComponent))
    }

    var tintColor: Color {
        Color(.sRGB, red: tint.red, green: tint.green, blue: tint.blue, opacity: tint.alpha)
    }

    // referenced as NativeGlassParams.timerBlurred in CircleButton
    static let timerBlurred = NativeGlassParams(bluRadius: 20, intensity: 0.5, tintColor: .clear)
}
