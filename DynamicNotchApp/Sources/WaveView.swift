import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import SwiftUI

// SwiftUI wrapper around WaveNSView for wave animation.
//   Updates the underlying NSView when frequency/amplitude bindings change.
// wrapper adapted to WaveNSView's real properties (volume/color/isPlaying)
struct WaveView: NSViewRepresentable {

    var volume: Double = 1.0
    var color: NSColor = .white
    var isPlaying: Bool = false

    func makeNSView(context: Context) -> WaveNSView {
        WaveNSView(frame: .zero)
    }

    func updateNSView(_ nsView: WaveNSView, context: Context) {
        nsView.volume = volume
        nsView.color = color
        if nsView.isPlaying != isPlaying { nsView.isPlaying = isPlaying }
    }
}
