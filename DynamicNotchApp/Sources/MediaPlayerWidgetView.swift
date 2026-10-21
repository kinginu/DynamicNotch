import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// The Nook "Media Player" widget. The width comes from the widget grid
//   (NookWidgetLayout: .doubleWide = 250 pt); the view fills the cell it is given.

struct MediaPlayerWidgetView: View {

    @Environment(\.nookSettings) private var nookSettings

    @Environment(\.mediaWidgetSettings) private var mediaWidgetSettings

    // position of the widget in the row (used by paddingDependingOnArrPos)
    var arrayPosition: ArrayPosition? = nil

    private var mediaManager = MediaManager.shared

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            if mediaManager.track != Track.empty {  // "has media" = a track is loaded
                MediaPlayerView()
                    .transition(.opacity)
            } else {
                NoMediaAppsView()
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.3), value: mediaManager.track == Track.empty)
        .nookWidgetFrame(alignment: .center)
        .foregroundStyle(.primary)
        .nookWidgetGalleryHook()
    }
}
