import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import QuickLookThumbnailing

// File icon: QuickLook thumbnail when available (generated asynchronously), else
//   nonShockingWhite if isImage, stroked Rectangle overlay with shadow).
struct TrayFileIconView: View {
    var file: TrayFile
    @State private var thumbnail: NSImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable(capInsets: EdgeInsets(), resizingMode: .stretch)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            } else {
                file.image
                    .resizable(capInsets: EdgeInsets(), resizingMode: .stretch)
                    .aspectRatio(contentMode: .fit)
            }
        }
        .task(id: file.url) {
            thumbnail = await TrayThumbnails.thumbnail(for: file.url, side: 128)
        }
    }
}
