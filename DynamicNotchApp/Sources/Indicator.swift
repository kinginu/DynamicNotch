import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
import Foundation

// HUD indicator model: UUID id, volume/brightness kind, optional label text and a Double value.
//   Kind is String-backed so its hash is stable.

struct Indicator: Equatable, Hashable, Identifiable {

    // MARK: - Stored Properties

    var id: UUID

    var kind: Kind

    var text: String?

    var value: Double

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)

        hasher.combine(kind)

        // Hashes optional text
        if let text = text {
            hasher.combine(1 as UInt8)
            hasher.combine(text)
        } else {
            hasher.combine(0 as UInt8)
        }

        hasher.combine(value)
    }

    // MARK: - Indicator.Kind

    enum Kind: String, Equatable, Hashable, RawRepresentable {
        case brightness = "brightness"
        case volume = "volume"
    }
}
