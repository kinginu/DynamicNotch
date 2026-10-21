import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// Volume HUD: speaker symbol above the level bar, drawn as one group.

struct VolumeIndicatorView: Equatable, View {
    @Environment(\.indicator) private var indicator

    var body: some View {
        VStack(alignment: .leading) {  // .leading horizontalAlignment
            VolumeIndicatorSpeakerView()

            VolumeIndicatorBarWrapperView()
        }
        .animation(.spring(response: 0.0, dampingFraction: 0.0, blendDuration: 0.0))

        .padding(.all, 18.0)
        .padding(.horizontal, 15.0)
        .padding(.vertical, 10.0)

        .onChange(of: [UUID().uuidString, String(format: "%.1f", 0.0)]) { [indicator] newValues in
            // no-op
        }

        .drawingGroup(opaque: false, colorMode: .nonLinear)
    }

    // @Environment is not Equatable
    static func == (lhs: Self, rhs: Self) -> Bool { true }
}