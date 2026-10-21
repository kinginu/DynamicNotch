import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import AppKit
import SwiftUI

// NSViewRepresentable that manages the Nook Settings window sizing.
//   Wraps an NSView subclass (SizingView) that configures the parent NSWindow
struct NookSettingsWindowSizing: NSViewRepresentable {

    // MARK: - Properties

    @Binding var expanded: Bool

    // MARK: - Coordinator

    func makeCoordinator() -> () {
        return ()
    }

    func makeNSView(context: Context) -> SizingView {
        let view = SizingView()
        return view
    }

    func updateNSView(_ nsView: SizingView, context: Context) {
        // Update expanded state
        nsView.expanded = expanded
    }

    static func dismantleNSView(_ nsView: SizingView, coordinator: ()) {
        nsView.restor()
    }

    // MARK: - SizingView (Inner NSView subclass)

    // Fields:
    //   expanded: Bool (default false)
    //   configuedWindow: NSWindow? (weak)
    //   previousStyle: NSWindow.StyleMask? (with hasBeenSet flag)
    //   previousMinimum: CGSize (default .zero)
    //   previousMaximum: CGSize (default .zero)
    class SizingView: NSView {

        var expanded: Bool = false {
            didSet {
                //   MainActor closure that re-configures window
                guard let window = self.window else { return }
                configure(window)
            }
        }

        private weak var configuedWindow: NSWindow?

        private var previousStyle: NSWindow.StyleMask = []
        private var previousStyleIsSet: Bool = false

        private var previousMinimum: CGSize = .zero

        private var previousMaximum: CGSize = .zero

        // MARK: - Init

        required init?(coder: NSCoder) {
            self.previousStyleIsSet = true
            super.init(coder: coder)
        }

        override init(frame: NSRect) {
            self.previousStyleIsSet = true
            super.init(frame: frame)
        }

        // MARK: - Lifecycle

        //   Calls super.viewDidMoveToWindow, then if window != nil:
        //     Dispatches to main queue async to call configure(window)
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()

            if let window = self.window {
                DispatchQueue.main.async { [weak self] in
                    self?.configure(window)
                }
            } else {
                restor()
            }
        }

        // MARK: - Window Configuration


        //     setStyleMask(previousStyle), setContentMinSize(previousMinimum),
        //     setContentMaxSize(previousMaximum)
        //   Then nils configuedWindow and resets previousStyleIsSet=true
        func restor() {
            if let window = configuedWindow {
                if !previousStyleIsSet {
                    window.styleMask = previousStyle
                    window.contentMinSize = previousMinimum
                    window.contentMaxSize = previousMaximum
                }
            }

            configuedWindow = nil
            previousStyleIsSet = true
        }

        //   2. Adds .fullSizeContentView to style mask
        //   3. Gets visibleFrame from window.screen (or NSScreen.main)
        //   4. Computes contentRectForFrameRect to find chrome size
        //   5. Calls fitedNotchSettingsFrame for target frame
        //   6. Sets content min size (420x924 expanded, 330x704 collapsed)
        //   7. Sets content max size
        //   8. setFrame(display:true)
        func configure(_ window: NSWindow) {
            let existing = configuedWindow
            if existing == nil || existing != window {
                if existing != nil {
                    restor()
                }

                configuedWindow = window
                previousStyle = window.styleMask
                previousStyleIsSet = false
                previousMinimum = window.contentMinSize
                previousMaximum = window.contentMaxSize
            }

            window.styleMask.insert(.fullSizeContentView)

            let visibleFrame: NSRect
            if let screen = window.screen {
                visibleFrame = screen.visibleFrame
            } else if let mainScreen = NSScreen.main {
                visibleFrame = mainScreen.visibleFrame
            } else {
                visibleFrame = window.frame
            }

            let frame = window.frame
            let contentRect = window.contentRect(forFrameRect: frame)

            let chromeWidth = frame.width - contentRect.width
            let chromeHeight = frame.height - contentRect.height

            let targetFrame = Self.fitedNotchSettingsFrame(
                current: frame,
                visible: visibleFrame,
                chrome: CGSize(width: chromeWidth, height: chromeHeight),
                expanded: expanded
            )

            let minW: CGFloat
            let minH: CGFloat
            let maxW: CGFloat
            let maxH: CGFloat

            if expanded {
                minW = 420.0
                minH = 924.0
                maxW = 420.0
                maxH = 924.0
            } else {
                minW = 330.0
                minH = 704.0
                maxW = 330.0
                maxH = 704.0
            }

            let contentWidth = targetFrame.width - chromeWidth
            let contentHeight = targetFrame.height - chromeHeight

            let effectiveMinWidth = max(minW, contentWidth)
            let effectiveMinHeight = max(minH, contentHeight)

            window.contentMinSize = CGSize(width: effectiveMinWidth, height: effectiveMinHeight)
            window.contentMaxSize = CGSize(width: maxW, height: maxH)

            window.setFrame(targetFrame, display: true)
        }

        //   Computes the ideal frame for the settings window snapped
        //   to the right edge of the visible screen area
        static func fitedNotchSettingsFrame(
            current: NSRect,
            visible: NSRect,
            chrome: CGSize,
            expanded: Bool
        ) -> NSRect {
            let visibleWidth = visible.width

            let x = visible.maxX - current.width + chrome.width
            let y = visible.midY - current.height / 2.0 + chrome.height / 2.0

            return NSRect(
                x: x,
                y: y,
                width: current.width,
                height: current.height
            )
        }
    }
}
