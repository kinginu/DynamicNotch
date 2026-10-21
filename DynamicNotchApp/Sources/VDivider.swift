import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// Invisible, non-hit-testable vertical spacer.

struct VDivider: View {
    var body: some View {
        // Color with opacity(0) — creates an invisible spacer/divider
        Color.clear
            .opacity(0)  // opacity(0)

            //   maxHeight=.infinity, center alignment
            .frame(minWidth: 0, idealWidth: 1, maxWidth: nil,
                   minHeight: 0, idealHeight: 1.0, maxHeight: .infinity,
                   alignment: .center)

            .allowsHitTesting(false)
    }
}