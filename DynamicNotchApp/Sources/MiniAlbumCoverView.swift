import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// View hierarchy : VStack(center, spacing:0) > Button(AlbumCoverView.padding.matchedGeometryEffect(id:), ShrinkOnClick)
//   > scaleEffect(quickPeekScaling) > animation(bouncySmooth, value: concatenatedTrackId) > onHover > onChange(of: trackId)
//   > onAppear { } > flexFrame(bottomLeading)
// closed-notch media artwork (leading side of the `.media` live activity). The row is
//   not hit-testable, so the original Button/hover handlers are dropped.

struct MiniAlbumCoverView: Equatable, View {

    private var mediaManager = MediaManager.shared

    // this screen's state (per-screen states); was DynamicNotchState.shared
    @Environment(\.dynamicNotchState) private var envNookState
    private var nookState: DynamicNotchState { envNookState ?? .shared }

    @StoredSetting(.mediaLiveActivitySettings) private var settings

    var body: some View {
        let radius = min(max(settings.albumCornerRadius, 0), 10)
        ZStack {
            if let art = mediaManager.track.albumArtImage {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.scaleAndBlur)
            } else {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                Image(systemName: "music.note")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.nonShockingWhite)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .scaleEffect(quickPeekScaling)  // quickPeekScaling from DynamicNotchState.quickPeeks
        .animation(.bouncySmooth, value: concatenatedTrackId)
    }

    // views hold only singletons/namespace; treat all instances as equal
    static func == (lhs: Self, rhs: Self) -> Bool { true }

    // MARK: - Quick Peek Scaling

    // 1.05 when the first quick peek is anchored .topLeading, else 1.0
    private var quickPeekScaling: Double {
        guard let quickPeeks = nookState.quickPeeks else { return 1.0 }
        return quickPeeks.first?.anchor == .topLeading ? 1.05 : 1.0
    }

    // MARK: - Animation value

    private var concatenatedTrackId: String {
        let track = mediaManager.track
        return track.id + track.metaId + String(describing: track.isPlaying) + track.albumId + track.title
    }
}
