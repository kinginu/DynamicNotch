import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
import SwiftUI

struct BrightnessIndicatorBarWrapperView: Equatable, View {
    // value forwarded to BrightnessIndicatorValueView (its init requires it)
    var brightness: Double = 0
    var glowThreshold: Double = 0

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading) {
                // BrightnessIndicatorValueView: framed with geometry width
                BrightnessIndicatorValueView(brightness: brightness, glowThreshold: glowThreshold)
                    .frame(
                        width: geometry.size.width,   // from GeometryProxy
                        height: nil as CGFloat?,
                        alignment: .center
                    )
                // BrightnessIndicatorCometView: framed with geometry width
                BrightnessIndicatorCometView()
                    .frame(
                        width: geometry.size.width,   // from GeometryProxy
                        height: 23.0,
                        alignment: .center
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 23.0, alignment: .leading)
        // padding(.horizontal) — EdgeInsets(all=0)
        .padding(.horizontal, 0)
    }
}
