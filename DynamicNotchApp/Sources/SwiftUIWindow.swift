import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
//
//   Reads self.onClose (optional closure property) 
//   If onClose is not nil, calls it (invokes stored closure) then releases it 
//   windowWillClose is triggered by the system Notification 

import Foundation
import AppKit

// Base class for SwiftUI-backed windows, likely NSWindow subclass
class SwiftUIWindow: NSWindow {

    var onClose: (() -> Void)?

    func windowWillClose(_ notification: Notification) {
        //   Clears the window's content view to break retain cycles and prepare for deallocation
        contentView?.removeFromSuperview()
        contentView = nil

        // Read self.onClose optional closure
        if let callback = onClose {
            // Invoke the stored closure
            callback()
            // Release the closure after invocation
            onClose = nil
        }
    }
}