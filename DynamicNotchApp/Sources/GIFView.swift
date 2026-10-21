import Foundation
import AppKit
import SwiftUI

// "Custom GIF" effect of the media live activity. Plays the GIF file the user picked in
// Settings › Live Activities › Media; when none is set (or the file is gone) it falls back to the
// SwiftUI-drawn equaliser bars (AudioBarsView). The app bundles no GIFs (removed 2026-10-20).
struct GIFView: View {
    @Environment(\.mediaLiveActivitySettings) private var settings: MediaLiveActivitySettings

    var size: CGSize

    private var mediaManager = MediaManager.shared

    init(size: CGSize) {
        self.size = size
    }

    var currentURL: URL? {
        guard let customURL = settings.customGifURL,
              FileManager.default.fileExists(atPath: customURL.path) else { return nil }
        return customURL
    }

    var body: some View {
        if let url = currentURL {
            GeometryReader { geometry in
                GIFImageView(url: url)
                    .frame(width: size.width, height: size.height, alignment: .center)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    .animation(.easeOut(duration: 0.3), value: url)
            }
        } else {
            AudioBarsView(isPlaying: mediaManager.isPlaying, color: .nonShockingWhite)
                .frame(width: min(size.width, 20), height: min(size.height, 14))
        }
    }
}
