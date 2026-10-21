import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// Color.clear with frame(width, height) from environment CGSize
// If width == 0: uses GeneralSettings environment for fallback size
// identity transition applied
struct TopBarSpacerView: View {
    @Environment(\.generalSettings) private var settings: GeneralSettings
    @Environment(\.notchSize) private var notchSize: CGSize

    var body: some View {
        Color.clear
            .frame(
                // GeneralSettings has no nookWidth/nookHeight; use \.notchSize, widgetWidth as fallback
                width: notchSize.width != 0 ? notchSize.width : settings.widgetWidth,
                height: notchSize.height
            )
            .transition(.identity)
    }
}