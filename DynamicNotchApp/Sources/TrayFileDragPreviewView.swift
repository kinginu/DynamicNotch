import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

//   TrayFileIconView + Text with a RoundedRectangle background).
struct TrayFileDragPreviewView: View {
    var file: TrayFile
    var count: Int = 1

    var body: some View {
        VStack(spacing: 4) {
            TrayFileIconView(file: file)
                .frame(width: 56, height: 56)
            Text(count > 1 ? "\(file.nameTruncated) +\(count - 1)" : file.nameTruncated)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor))
                .foregroundStyle(Color.white)
        }
        .padding(4)
    }
}
