import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import SwiftUI

// Glass-morphism tab button with advanced visual effects
//   (blur, gradient overlay, border highlights). Used in settings tabs.
struct AdvancedGlassTab: View {

    // Tab title
    var title: String

    // Whether this tab is currently selected
    var isSelected: Bool

    // Action when tapped
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .buttonStyle(ShrinkOnPressButtonStyle())
        .glassButtonIfEnabled(isSelected)
    }
}
