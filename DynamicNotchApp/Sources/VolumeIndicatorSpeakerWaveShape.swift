import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// Concentric arcs to the right of the speaker,
//   `level` (0…1, animatable) decides how many of `waveCount` arcs are drawn.
struct VolumeIndicatorSpeakerWaveShape: Animatable, Shape, View {
    var level: Double = 1
    var waveCount: Int = 3

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.minX, y: rect.midY)
        let maxRadius = min(rect.width, rect.height / 2)
        let visible = Int((level * Double(waveCount)).rounded(.up))
        guard visible > 0 else { return path }
        for i in 1...min(visible, waveCount) {
            let r = maxRadius * CGFloat(i) / CGFloat(waveCount)
            path.move(to: CGPoint(x: center.x + r * cos(.pi / 4), y: center.y - r * sin(.pi / 4)))
            path.addArc(center: center, radius: r, startAngle: .degrees(-45), endAngle: .degrees(45), clockwise: false)
        }
        return path
    }
}
