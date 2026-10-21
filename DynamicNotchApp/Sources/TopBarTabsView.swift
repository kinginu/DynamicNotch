import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import SwiftUI

// Renders the tab switcher (Nook / Tray) in the top bar.
// tabs select the mode through DynamicNotchState.select(_:); the labelled tabs
//   collapse to icon-only tabs when the space left of the camera housing is narrow.
struct TopBarTabsView: View {

    // Current active notch mode
    @Environment(\.notchMode) private var notchMode: DynamicNotchState.NotchMode?
    // this screen's notch state (per-screen states)
    @Environment(\.dynamicNotchState) private var envNookState

    // All available modes for tabs
    private let modes: [DynamicNotchState.NotchMode] = [.nook, .tray] // real NotchMode cases

    // Namespace for matched geometry animation
    @Namespace private var namespace

    private var activeMode: DynamicNotchState.NotchMode {
        notchMode == .tray || notchMode == .dragging ? .tray : .nook
    }

    // MARK: - Body

    var body: some View {
        ViewThatFits(in: .horizontal) {
            tabs(showLabels: true)
            tabs(showLabels: false)
        }
    }

    private func tabs(showLabels: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(modes, id: \.self) { mode in
                TopBarTabView(
                    icon: Self.icon(for: mode),
                    label: Self.label(for: mode),
                    isActive: mode == activeMode,
                    showLabel: showLabels,
                    namespace: namespace
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        (envNookState ?? .shared).select(mode)
                    }
                }
            }
        }
        .fixedSize()
    }

    static func icon(for mode: DynamicNotchState.NotchMode) -> String {
        mode == .tray ? "tray.fill" : "square.grid.2x2.fill"
    }

    static func label(for mode: DynamicNotchState.NotchMode) -> String {
        mode == .tray ? String(localized: "Tray") : String(localized: "Nook")
    }

    // MARK: - getHeight

    // Computes bar height for given available height
    func getHeight(_ available: CGFloat) -> CGFloat {
        return min(available, 28)
    }
}
