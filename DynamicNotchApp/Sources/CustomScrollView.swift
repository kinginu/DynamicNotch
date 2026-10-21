import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
import AppKit

// NSScrollView whose scroll wheel scrolls vertically only (clamped to the document); horizontal
//   and trackpad-dominant-horizontal scrolling go to super.

class CustomScrollView: NSScrollView {

    override func scrollWheel(with event: NSEvent) {
        let absDeltaY = abs(event.scrollingDeltaY)
        let absDeltaX = abs(event.scrollingDeltaX)

        // If |deltaY| <= |deltaX|, delegate to super (horizontal/trackpad scroll)
        if absDeltaY <= absDeltaX {
            super.scrollWheel(with: event)
            return
        }

        let contentView = self.contentView // contentView is non-optional

        // Get current scroll origin from contentView.bounds
        let currentBounds = contentView.bounds
        let currentOriginY = currentBounds.origin.y
        let currentOriginX = currentBounds.origin.x

        guard let documentView = self.documentView else {
            return
        }

        let documentFrame = documentView.frame
        let documentHeight = documentFrame.size.height

        let contentViewportHeight = contentView.bounds.size.height

        let maxScrollY = documentHeight - contentViewportHeight

        var newOriginY = currentOriginY - event.scrollingDeltaY

        if newOriginY < 0.0 {
            newOriginY = 0.0
        } else if newOriginY > maxScrollY {
            newOriginY = maxScrollY
        }

        contentView.scroll(to: NSPoint(x: currentOriginX, y: newOriginY))

        self.reflectScrolledClipView(contentView)
    }
}
