import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import SwiftUI

// Displays brightness level with glowing indicator bar
struct BrightnessIndicatorView: Equatable, View {

    // Current brightness level (0.0...1.0)
    var level: CGFloat = 0.5

    // Whether indicator is currently active/visible
    var isActive: Bool = false

    // MARK: - glowColor

    // Yellow-amber glow color proportional to brightness level
    var glowColor: Color {
        // Lerp from dim amber to bright yellow
        let brightness = max(level, 0.1)
        if isActive {
            return Color.yellow.opacity(brightness)
        }
        return Color(white: 0.6).opacity(brightness * 0.5)
    }

    // MARK: - Body

    // Horizontal brightness bar with glow effect
    var body: some View {
        HStack(spacing: 2) {
            // Sun icon
            Image(systemName: level > 0.5 ? "sun.max.fill" : "sun.min")
                .foregroundStyle(glowColor)
                .font(.caption)

            // Progress bar
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(.secondary.opacity(0.2))
                        .frame(height: 4)

                    // Filled portion
                    Capsule()
                        .fill(glowColor)
                        .frame(width: proxy.size.width * level, height: 4)
                }
                .shadow(color: glowColor, radius: 4)
            }
            .frame(width: 60)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }
}