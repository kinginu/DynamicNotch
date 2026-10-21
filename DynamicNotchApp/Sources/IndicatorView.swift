import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// Routes the current Indicator to the
//   volume / brightness HUD. NotchView calls it with no arguments.
struct IndicatorView: View {
    @Environment(\.indicator) private var envIndicator

    private var indicator: Indicator? { envIndicator ?? DynamicNotchState.shared.indicator }

    var body: some View {
        Group {
            if let indicator {
                switch indicator.kind {
                case .volume:
                    VolumeIndicatorView()
                        .environment(\.indicator, indicator)
                case .brightness:
                    BrightnessIndicatorBarWrapperView(brightness: indicator.value)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                }
            }
        }
    }
}
