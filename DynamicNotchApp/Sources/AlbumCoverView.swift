import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import SwiftUI

struct AlbumCoverView: Equatable, Identifiable, View {
    @State private var albumArt: NSImage? = nil

    // Identity derived from MediaManager track index or persistent ID
    var id: Int = 0

    // Modifier chain: ZStack > rotation3DEffect(angle * 0.01745, z-axis, center) > .animation(.bouncySmooth) > .transition(.scaleAndBlur)
    // rotations3DEffect angle multiplier 0.01745... = Double.pi / 180 (degrees-to-radians conversion)
    // Rotation angle driven by albumArt?.averageColor or MediaManager._track property
    var body: some View {
        ZStack {
            if let art = albumArt ?? MediaManager.shared.track.albumArtImage {  // fall back to track artwork
                Image(nsImage: art)
                    .resizable()                                        // Resizable modifier from layout pattern
                    .aspectRatio(contentMode: .fill)                    // Fill content mode for album art
            }
        }
        .rotation3DEffect(
            .degrees(0),                                                // Angle sourced from albumArt.averageColor or MediaManager track
            axis: (x: 0, y: 0, z: 1),
            anchor: .center
        )
        .animation(.bouncySmooth, value: albumArt)

        .transition(.scaleAndBlur)
    }

    // Equatable by id (@State is not Equatable)
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}
