import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import SwiftUI
import AppKit

// wraps AudioSpectrographNSView (declared in AudioSpectrographNSView.swift). The
//   original file also contained a second, conflicting AudioSpectrographNSView class; it was
//   dropped in favour of the other one.
struct AudioSpectrographView: NSViewRepresentable, View {

    // animate bars while playing
    var isPlaying: Bool = true

    // bar tint
    var color: NSColor = .white

    func makeNSView(context: NSViewRepresentableContext<AudioSpectrographView>) -> AudioSpectrographNSView {
        let view = AudioSpectrographNSView(frame: .zero)
        view.color = color
        return view
    }

    func updateNSView(_ nsView: AudioSpectrographNSView, context: NSViewRepresentableContext<AudioSpectrographView>) {
        nsView.color = color
        if nsView.isPlaying != isPlaying {
            nsView.isPlaying = isPlaying
        }
        if isPlaying { nsView.startAnimation() } else { nsView.stopAnimation() }
    }

    static func dismantleNSView(_ nsView: AudioSpectrographNSView, coordinator: ()) {
        nsView.cleanup()
    }
}
