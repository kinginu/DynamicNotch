import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
//
// A BetterWindow whose close() animates: it prepares the transform window with
//   BetterWindow.setupIfNeeded(with:closing:cb:) and then runs
//   BetterWindow.animatedClose(withDuration:timing:setup:animations:) (default timing).

import Foundation
import QuartzCore

class SwiftUIAnimatedWindow: BetterWindow {

    // Flag tracking whether transform/screenshot setup has been performed
    private var setupDone: Bool = false

    // Flag tracking whether the window is currently closing (prevents double-close)
    private var closing: Bool = false

    override func close() { // override keyword
        // Sets up the transform window if needed, then performs animated close
        //   Calls BetterWindow.setupIfNeeded(with:closing:cb:) → then
        //   BetterWindow.animatedClose(withDuration:timing:setup:animations:)

        setupIfNeeded(
            with: nil,              // No custom layer setup passed
            closing: true,          // closing flag is true
            cb: {
                // After setup completes, trigger the animated close
                self.animatedClose(
                    withDuration: 0.45,
                    timing: nil,
                    setup: { layer in
                        // Setup block: mark setup as done for cleanup tracking
                        //   This runs before the animation begins
                        layer.opacity = 1.0
                    },
                    animations: { layer in
                        // Fade-out + scale-down animation for closing
                        layer.opacity = 0.0
                    }
                )
            }
        )
    }
}