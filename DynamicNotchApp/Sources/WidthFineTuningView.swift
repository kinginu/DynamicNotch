import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// Width fine-tuning label: semibold numeric text on the fine-tuning background.

struct WidthFineTuningView: View {

    var body: some View {
        HStack {
            Color.fineTuningBG
                .frame(minWidth: 0, idealWidth: 8.0, maxWidth: nil,
                       minHeight: 0, idealHeight: 1, maxHeight: nil,
                       alignment: .center)

            Color.clear
                .compositingGroup()
                .opacity(1.0)

            Text("Width")  // localized label text
                .contentTransition(.opacity)
                .fixedSize(horizontal: true, vertical: true)
                .foregroundColor(.white)
                // fontWeight(.semibold) — weight modifier on View extension
                .fontWeight(.semibold)
        }
        .compositingGroup()
        .opacity(1.0)

        .padding(12.0)

        // width derived from CGSize environment value
        .frame(width: 0, height: 1, alignment: .center)

        .animation(.spring(response: 0.5, dampingFraction: 0.0, blendDuration: 0.0), value: 0) // value-less animation() is unavailable

        .transition(.opacity)
    }
}