import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import AppKit
import SwiftUI

// An inset glass bubble shape — rounded rectangle with
//   an inner "bubble" effect for depth. Used inside glass containers.
struct InsetGlassBubbleShape: Animatable, Shape, View {

    // Inset amount from the rect edges
    var inset: CGFloat = 4.0

    // Corner radius for the bubble
    var cornerRadius: CGFloat = 12.0

    var animatableData: CGFloat {
        get { inset }
        set { inset = newValue }
    }

    func path(in rect: CGRect) -> Path {
        // Inset rounded rect path
        let insetRect = rect.insetBy(dx: inset, dy: inset)
        return Path(roundedRect: insetRect, cornerRadius: cornerRadius)
    }

    var body: some View {
        self
            .fill(.ultraThinMaterial)
            .overlay(
                self.stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.2), .white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            )
    }
}
