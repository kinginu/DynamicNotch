import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

// Scales, blurs and fades the content; drives the `.scaleAndBlur` transition.
struct ScaleAndBlurEffect: ViewModifier {
    /// 0 = removed (small, blurred, transparent), 1 = identity.
    var progress: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .scaleEffect(0.8 + 0.2 * progress)
            .blur(radius: (1 - progress) * 8)
            .opacity(Double(progress))
    }
}
