import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

// Wraps NativeGlassParams; Codable auto-synthesized by compiler
struct LiquidGlassSettings: Preferences, Decodable, Encodable, Equatable, Hashable {
    // Returns stored NativeGlassParams; default value from synthesized memberwise init
    var params: NativeGlassParams = NativeGlassParams()

    // Auto-synthesized Encodable conformance

    // Auto-synthesized from Hashable conformance

    // MARK: - CodingKeys

    // Auto-synthesized CodingKey enum
}
