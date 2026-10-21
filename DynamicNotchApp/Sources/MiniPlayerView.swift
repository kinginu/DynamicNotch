import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// Mini player: album cover and media controls, animated with .bouncySmooth when the track changes.

import SwiftUI

struct MiniPlayerView: View {

    private var mediaManager = MediaManager.shared

    var body: some View {
        GeometryReader { _ in
            VStack(alignment: .center) {
                HStack {
                    AlbumCoverView()
                        .padding(.all, 4)

                    MediaControlsView()
                }
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .flexFrame(minWidth: nil, idealWidth: nil, maxWidth: .infinity, minHeight: nil, idealHeight: nil, maxHeight: nil, alignment: .center)
        .animation(.bouncySmooth, value: concatenatedTrackId)
    }

    // views hold only singletons/namespace; treat all instances as equal
    static func == (lhs: Self, rhs: Self) -> Bool { true }

    // MARK: - Animation value

    private var concatenatedTrackId: String {
        let track = mediaManager.track
        var result = track.id
        result += track.metaId
        result += String(describing: track.isPlaying)
        result += track.albumId
        result += track.title
        return result
    }
}
