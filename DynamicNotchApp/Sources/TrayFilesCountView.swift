import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

//   transition, semibold system font, nonShockingWhite). Used by the tray header and by the
//   `.tray` live activity (LiveActivityView calls it without arguments → live count).
struct TrayFilesCountView: View {
    var count: Int? = nil

    var body: some View {
        HStack(spacing: 3) {
            Text("\(count ?? Tray.shared.files.count)")
                .contentTransition(.numericText())
                .monospacedDigit()
            Image(systemName: "doc.fill")
                .imageScale(.small)
        }
        .font(.system(size: 12, weight: .semibold, design: .default))
        .foregroundStyle(Color.nonShockingWhite)
        .fixedSize()
    }
}
