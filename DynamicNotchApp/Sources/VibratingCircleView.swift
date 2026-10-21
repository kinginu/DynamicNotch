import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import SwiftUI

// SwiftUI wrapper around VibratingCircleNSView for vibration animation.
//   Updates the underlying NSView when the phase/progress binding changes.
// wrapper adapted to VibratingCircleNSView's real properties (color/isPlaying/amplitude)
struct VibratingCircleView: NSViewRepresentable {

    var color: NSColor = .white
    var isPlaying: Bool = false
    var amplitude: CGFloat = 4.0

    func makeNSView(context: Context) -> VibratingCircleNSView {
        VibratingCircleNSView(frame: .zero)
    }

    func updateNSView(_ nsView: VibratingCircleNSView, context: Context) {
        nsView.color = color
        nsView.amplitude = amplitude
        if nsView.isPlaying != isPlaying {
            nsView.isPlaying = isPlaying
            if isPlaying { nsView.startAnimating() } else { nsView.stopAnimating() }
        }
    }
}
