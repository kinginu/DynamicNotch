import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
//
//   1. Create KeyedEncodingContainer<NookGrid.Size.CodingKeys>
//
//
// NookGrid is a layout grid system. Size has width and height as Point values.
//   Point is Comparable (based on double value), used for widget sizing.

import Foundation

struct NookGrid {
}

// MARK: - NookGrid.Size
extension NookGrid {
    struct Size: Decodable, Encodable, Equatable, Hashable {
        //   CodingKeys enum with string values "width" and "height"
        var width: Point
        var height: Point

        //   1. container(keyedBy: CodingKeys.self)
        //   2. try container.encode(width, forKey: .width)   → key 0 / string "width"
        //   3. try container.encode(height, forKey: .height) → key 1 / string "height"
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            //   __ss22KeyedEncodingContainerV6encode_6forKeyyqd___xtKSERd__lF
            try container.encode(width, forKey: .width)

            try container.encode(height, forKey: .height)
        }

        enum CodingKeys: String, CodingKey {
            case width
            case height
        }
    }
}

// MARK: - NookGrid.Point
extension NookGrid {
    struct Point: Decodable, Encodable, Equatable, Hashable, Comparable {
        // Point stores a single Double value
        var value: Double

        //   The Point's double property returns its stored value as Double
        var double: Double {
            return value
        }

        static func < (lhs: Point, rhs: Point) -> Bool {
            return lhs.value < rhs.value
        }

        static func == (lhs: Point, rhs: Point) -> Bool {
            return lhs.value == rhs.value
        }

        // Hashable conformance
        func hash(into hasher: inout Hasher) {
            hasher.combine(value)
        }
    }
}
