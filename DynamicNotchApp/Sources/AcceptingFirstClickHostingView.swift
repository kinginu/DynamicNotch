import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import AppKit
import SwiftUI

// Generic NSHostingView subclass that overrides acceptsFirstMouse
//   to return true, allowing the hosted SwiftUI view to receive the
//   initial mouse-down event even when the window is inactive.
//   This is critical for the Notch overlay interaction model.
class AcceptingFirstClickHostingView<Content: View>: NSHostingView<Content> {

    // standard initialisers only (init(coder:rootView:) would need macOS 15.4+)
    @MainActor required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    //   Delegates to super.init(coder:)
    @MainActor required dynamic init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // acceptsFirstMouse is a method on NSView, not a property
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}
