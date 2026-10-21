import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// Chips to switch between now-playing sources (MediaManager.nowPlayingSources); hidden with fewer
//   than two sources.
struct NowPlayingSourceSwitcherView: View {
    private var mediaManager: MediaManager = .shared  // @Observable class, not ObservableObject

    var body: some View {
        let sources = mediaManager.nowPlayingSources

        if sources.count >= 2 {
            HStack(alignment: .center, spacing: 24) {
                ForEach(sources, id: \.self) { source in
                    SourceChipView(source: source)
                }
            }
            .transition(
                .scaleAndBlur.combined(with: .identity)  // SharedDeclarations.swift's scaleAndBlur takes no parameters
            )
        }
    }
}