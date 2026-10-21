import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import SwiftUI

// Volume level indicator with segmented bar display
struct VolumeIndicatorBarView: Equatable, View {

    // Current volume level (0.0...1.0)
    var volume: CGFloat = 0.5

    // Total number of bar segments
    private let barCount: Int = 16

    // MARK: - volumeLastBar

    // Number of bars that should be lit at current volume
    var volumeLastBar: Int {
        Int((volume * CGFloat(barCount)).rounded(.toNearestOrAwayFromZero))
    }

    // MARK: - Body

    // HStack of colored capsule segments
    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(getBarColor(index: index))
                    .frame(width: 2, height: 12)
            }
        }
        .padding(.horizontal, 6)
    }

    // MARK: - getBarColor

    // getBarColor(index:) -> Color
    // Gradient from green through yellow to orange based on bar index
    func getBarColor(index: Int) -> Color {
        if index >= volumeLastBar {
            // Dimmed/inactive bars
            return Color.white.opacity(0.15)
        }

        // Active bars: green -> yellow -> orange gradient
        let ratio = CGFloat(index) / CGFloat(barCount - 1)
        if ratio < 0.5 {
            // Green to yellow
            let localRatio = ratio / 0.5
            return Color(
                red: localRatio,
                green: 1.0,
                blue: 0.0
            )
        } else {
            // Yellow to orange
            let localRatio = (ratio - 0.5) / 0.5
            return Color(
                red: 1.0,
                green: 1.0 - localRatio * 0.5,
                blue: 0.0
            )
        }
    }
}