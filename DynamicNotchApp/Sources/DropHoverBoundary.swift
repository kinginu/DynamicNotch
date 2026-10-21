import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import CoreGraphics

struct DropHoverBoundary {
    // boundary rect — initialized to null
    var boundary: CGRect = .null

    mutating func include(_ rect: CGRect?) {
        // guard: nil check returns early
        guard let rect = rect else { return }
        // if boundary is null, assign rect directly
        if boundary.isNull {
            boundary = rect
            // else union rect into boundary
        } else {
            boundary = boundary.union(rect)
        }
    }

    // hover-session state used by FileDropView.DropAreaView
    var sequence: Int? = nil
    var isHovering: Bool = false

    // begin/continue a hover for drag `sequence` over `frame`
    mutating func enter(sequence: Int, frame: CGRect) {
        if self.sequence != sequence {
            boundary = .null
            self.sequence = sequence
        }
        include(frame)
        isHovering = true
    }

    // pointer left the area (drag still alive)
    mutating func exit() {
        isHovering = false
    }

    // drag finished: reset all fields
    mutating func end() {
        boundary = .null
        sequence = nil
        isHovering = false
    }
}
