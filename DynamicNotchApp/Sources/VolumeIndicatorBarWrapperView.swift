import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// Volume HUD: the percentage label above the level bar.

struct VolumeIndicatorBarWrapperView: Equatable, View {
    var body: some View {
        GeometryReader { geometry in  // GeometryReader wrapper
            VStack {
                VolumeIndicatorValueView()
                    .frame(width: nil, height: nil, alignment: .leading)

                VolumeIndicatorBarCapsuleView(nsColor: .clear, isActive: true)  // placeholder
            }
            .frame(minWidth: 0, idealWidth: 1, maxWidth: nil,
                   minHeight: 0, idealHeight: 31.0, maxHeight: .infinity,
                   alignment: .leading)  // .leading
        }
        .padding(.all, 0)  // from EdgeInsets.all(0)
        .padding(.horizontal, 0)  // EdgeO3Set.horizontal
    }
}