import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import SwiftUI

// Individual tab in the top bar with icon, label, and an active background
// the active background is a sliding capsule (matchedGeometryEffect) instead of
//   the liquid-glass backdrop, which renders as an opaque slab outside the glass path.
struct TopBarTabView: View {

    // Tab icon name
    var icon: String

    // Tab label text
    var label: String

    // Whether this tab is the active one
    var isActive: Bool

    var showLabel: Bool = true

    var namespace: Namespace.ID? = nil

    // Action on tap
    var action: () -> Void

    // MARK: - activeBackground

    @ViewBuilder
    var activeBackground: some View {
        if isActive {
            if let namespace {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.16))
                    .matchedGeometryEffect(id: "topbar.activeTab", in: namespace)
            } else {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.16))
            }
        }
    }

    // MARK: - Body

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                if showLabel {
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, showLabel ? 9 : 7)
            .frame(height: 22)
            .foregroundStyle(Color.nonShockingWhite.opacity(isActive ? 1 : 0.55))
            .background(activeBackground)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(label)
    }
}
