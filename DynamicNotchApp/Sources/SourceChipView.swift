import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// Button with ZStack containing source icon Image
// scaledToFit, frame, clipShape RoundedRectangle, opacity conditional
// overlay Circle+Color shape, offset
// padding, background Color, ShrinkOnClick buttonStyle
// help(tooltip) and hoverRegion modifier
struct SourceChipView: View {
    let source: NowPlayingSource

    var body: some View {
        Button(action: {

            MediaManager.shared.userPinnedClientID = source.bundleIdentifier
        }) {
            ZStack {
                Image(systemName: source.iconName)
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .opacity(0.85)


                Circle()
                    .fill(Color.blue)
                    .frame(width: 6, height: 6)
                    .offset(x: 10, y: -10)
                    .opacity(source.isActive ? 1 : 0)
            }
        }
        .padding(6)
        .background(
            Circle()
                .fill(Color.nonShockingWhite.opacity(0.1))
        )
        .buttonStyle(ShrinkOnClick())
        .help(source.displayName)
    }
}