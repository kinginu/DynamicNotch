import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// Level bar capsule of the volume HUD: a filled capsule with three shadow layers and a lighter
//   stroked / gradient overlay.

struct VolumeIndicatorBarCapsuleView: View {
    var nsColor: NSColor
    var isActive: Bool

    var body: some View {
        // Convert NSColor to SwiftUI Color; creates lighter variant
        let color = Color(nsColor: nsColor)
        let lighterColor = nsColor.lighter(amount: 0.2)
        let lighterSwiftUIColor = Color(nsColor: lighterColor)

        Capsule()
            // Fill with the color
            .fill(color)

            //   conditional opacity: 1.0 if active else 0
            .shadow(color: lighterSwiftUIColor.opacity(isActive ? 1.0 : 0.0),
                    radius: 4.0, x: 0, y: 0)  // radius=4.0

            //   conditional opacity: 0 if inactive else 1.0
            .shadow(color: lighterSwiftUIColor.opacity(isActive ? 1.0 : 0.0),
                    radius: 16.0, x: 0, y: 0)  // radius=16.0

            //   conditional opacity: 0 if inactive else 1.0
            .shadow(color: lighterSwiftUIColor.opacity(0),
                    radius: 24.0, x: 0, y: 0)  // radius=24.0

            .overlay(
                ZStack(alignment: .center) {
                    Group {
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [.clear, .white.opacity(0.5)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                            .blendMode(.overlay)
                            .opacity(1.0)
                    }
                }
                .padding(0.5)
            )
    }
}