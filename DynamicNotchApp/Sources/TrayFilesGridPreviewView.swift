import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

//   fixedSize, compositingGroup). Used as the stack tile's picture.
struct TrayFilesGridPreviewView: View {
    var files: [TrayFile] = []
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            ForEach(Array(files.prefix(3).enumerated()), id: \.element.id) { index, file in
                TrayFileIconView(file: file)
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(Double(index - 1) * 8))
                    .offset(x: CGFloat(index - 1) * 7)
                    .zIndex(Double(3 - index))
            }
        }
        .frame(width: size + 18, height: size + 8)
        .compositingGroup()
    }
}
