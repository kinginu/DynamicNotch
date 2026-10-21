import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
//
// Reports the view's frame in screen coordinates (bounds → window → screen) whenever it moves
//   to a window or changes size / origin. NotchView uses it to track the hover frame.

import SwiftUI
import AppKit

//   The struct provides a transparent NSView that reports its screen frame
//   via a closure. Used by NotchView's gestures modifier for hit detection.
struct NotchHoverFrameReader: NSViewRepresentable {
    typealias NSViewType = Reader

    // The report closure — called with the view's screen-space frame
    var report: ((CGRect) -> Void)?

    func updateNSView(_ nsView: Reader, context: NSViewRepresentableContext<NotchHoverFrameReader>) {
        nsView.report = report

        // the view publishes its frame itself (viewDidMoveToWindow / setFrameSize / setFrameOrigin)
    }

    func makeNSView(context: NSViewRepresentableContext<NotchHoverFrameReader>) -> Reader {
        return Reader(frame: .zero)
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator()
    }

    struct Coordinator {}

    //   Subclass of NSView that tracks its screen position and reports it
    class Reader: NSView {
        //   Closure called with the view's frame in screen coordinates
        var report: ((CGRect) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()

            let viewBounds = self.bounds

            //   Converts to window coordinate space
            guard let window = self.window else {
                return
            }

            let windowRect = self.convert(viewBounds, to: nil)

            //   Converts to screen coordinate space
            let screenRect = window.convertToScreen(windowRect)

            if let report = report {
                report(screenRect)
            }
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            publishFrameIfNeeded()
        }

        override func setFrameOrigin(_ newOrigin: NSPoint) {
            super.setFrameOrigin(newOrigin)
            publishFrameIfNeeded()
        }

        // Shared publish logic extracted from both viewDidMoveToWindow and setFrameSize/Origin
        private func publishFrameIfNeeded() {
            guard let window = self.window else { return }

            let viewBounds = self.bounds
            let windowRect = self.convert(viewBounds, to: nil)
            let screenRect = window.convertToScreen(windowRect)

            if let report = report {
                report(screenRect)
            }
        }
    }
}
