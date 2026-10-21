import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// One row of the tutorial (`TutorialItemView()` in TutorialView).
struct TutorialItemView: View {
    var icon: String = "hand.tap"
    var title: LocalizedStringKey = "Hover over the notch"

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28))
            Text(title)
                .font(.callout)
        }
        .padding()
    }
}
