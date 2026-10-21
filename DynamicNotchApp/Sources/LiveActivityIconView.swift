import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// Image(systemName: activity.icon), font(.system(size:0, design:.default))
// nonShockingWhite foreground, flex frame
struct LiveActivityIconView: View {
    let activity: LiveActivity

    var body: some View {
        Image(systemName: activity.icon)
            .font(.system(size: 12, weight: .semibold, design: .default))  // size 0 rendered nothing
            .foregroundStyle(.nonShockingWhite)
            .fixedSize()
    }
}