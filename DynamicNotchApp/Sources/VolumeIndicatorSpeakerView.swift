import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// Volume HUD speaker symbol with its wave arcs (replace-symbol content transition, 16 pt semibold).

struct VolumeIndicatorSpeakerView: Equatable, View {

    var body: some View {
        HStack {
            Image(systemName: "speaker.wave.2")  // system symbol name

            HStack {
                VolumeIndicatorSpeakerWaveShape()  // custom shape
                    .stroke(Color.accentColor, style: StrokeStyle())
                    .padding(.all, 0)
            }
            .frame(width: 25.0, height: 22.0, alignment: .center)  // width=25.0, height=22.0
            .padding(.all, 0)
        }
        .contentTransition(.opacity)  // (was invalid .environment(\.contentTransition))

        // ReplaceSymbolEffect with .default options (SF Symbols effect)
        // removed .symbolEffect(.replace): replace is a content transition, not an indefinite effect

        .contentTransition(.symbolEffect(.replace))

        .frame(minWidth: nil, idealWidth: nil, maxWidth: nil,
               minHeight: nil, idealHeight: -1.0, maxHeight: nil,
               alignment: .center)

        .font(.system(size: 16.0, weight: .semibold, design: .default))

        .foregroundColor(.accentColor)
    }
}