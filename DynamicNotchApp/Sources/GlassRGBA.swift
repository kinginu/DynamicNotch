import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
import Foundation

struct GlassRGBA: Codable, Equatable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    // memberwise init (suppressed by the custom decoder init)
    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        red = try container.decode(Double.self, forKey: .red)
        green = try container.decode(Double.self, forKey: .green)
        blue = try container.decode(Double.self, forKey: .blue)
        alpha = try container.decode(Double.self, forKey: .alpha)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(red, forKey: .red)
        try container.encode(green, forKey: .green)
        try container.encode(blue, forKey: .blue)
        try container.encode(alpha, forKey: .alpha)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(red == 0.0 ? UInt64(0) : red.bitPattern)
        hasher.combine(green == 0.0 ? UInt64(0) : green.bitPattern)
        hasher.combine(blue == 0.0 ? UInt64(0) : blue.bitPattern)
        hasher.combine(alpha == 0.0 ? UInt64(0) : alpha.bitPattern)
    }

    enum CodingKeys: String, CodingKey, CustomStringConvertible, CustomDebugStringConvertible, Equatable, Hashable {
        case red
        case green
        case blue
        case alpha
    }
}
