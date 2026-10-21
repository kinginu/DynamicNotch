import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import SwiftUI

// Custom button style with glass morphism effect that adapts to dark/light mode
struct AdaptiveGlassButtonStyle: PrimitiveButtonStyle {

    // Configuration state
    private var isPressed: Bool = false

    // MARK: - makeBody

    // makeBody(configuration:) -> some View
    // Wraps label in MaterialCapsule with scale animation
    func makeBody(configuration: PrimitiveButtonStyleConfiguration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                MaterialCapsule()
            )
            // PrimitiveButtonStyleConfiguration has no isPressed; fire trigger on tap
            .contentShape(Rectangle())
            .onTapGesture { configuration.trigger() }
    }

    // MARK: - MaterialCapsule

    // MaterialCapsule nested struct
    // Capsule-shaped glass morphic background
    struct MaterialCapsule: View {

        // Glass tint color
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.2), lineWidth: 0.5)
                )
        }
    }
}