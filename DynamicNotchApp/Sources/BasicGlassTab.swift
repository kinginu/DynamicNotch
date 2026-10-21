import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import SwiftUI

// Basic glass-morphism tab button with simpler visual effects
//   than AdvancedGlassTab. Used in settings tabs for less prominent sections.
struct BasicGlassTab: View {

    // Tab title
    var title: String

    // Whether this tab is currently selected
    var isSelected: Bool

    // Action when tapped
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}
