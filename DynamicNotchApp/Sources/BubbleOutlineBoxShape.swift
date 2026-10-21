import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import AppKit
import SwiftUI

// A bubble-style rounded rectangle outline shape with
//   variable corner radius. Used as a decorative outline for glass containers.
struct BubbleOutlineBoxShape: Animatable, Shape, View {

    // Corner radius for the bubble outline
    var cornerRadius: CGFloat = 16.0

    // Stroke width
    var strokeWidth: CGFloat = 1.0

    // Animatable data for the corner radius
    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        // Rounded rect path
        let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        return Path(path)
    }

    var body: some View {
        self
            .fill(.clear)
            .overlay(self.stroke(LinearGradient(
                colors: [.white.opacity(0.3), .white.opacity(0.05)],
                startPoint: .top,
                endPoint: .bottom
            ), lineWidth: strokeWidth))
    }
}
