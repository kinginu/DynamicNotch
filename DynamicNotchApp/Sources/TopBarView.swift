import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

// Top bar container with tabs, background, spacer, and source chips
//
// NotchView renders TopBarView in the notch-height row above the open notch
//   (nook and tray modes; frame = open width × notch height). The hardware camera housing
//   covers the centre `notchSize.width`, so the bar is split around it: mode tabs (Nook / Tray)
//   on the left, the settings button on the right. It is always shown while the notch is open, so
//   Nook ↔ Tray can always be switched.
struct TopBarView: View {

    // Notch mode from environment
    @Environment(\.notchMode) private var notchMode: DynamicNotchState.NotchMode?
    @Environment(\.notchSize) private var notchSize: CGSize

    /// Inset from the open notch's rounded top corners.
    private let edgeInset: CGFloat = 14

    // MARK: - shouldHide

    var shouldHide: Bool {
        notchMode == nil || notchMode == .closed
    }

    // MARK: - Body

    var body: some View {
        if shouldHide {
            EmptyView()
        } else {
            HStack(spacing: 0) {
                // Tabs for mode switching
                TopBarTabsView()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, edgeInset)
                    .padding(.trailing, 6)

                // camera housing
                TopBarSpacerView()

                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    TopBarSettingsButton()
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 6)
                .padding(.trailing, edgeInset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.colorScheme, .dark)
        }
    }

    // MARK: - getHeight

    // getHeight(_:) -> CGFloat
    // Computes bar height from available space
    func getHeight(_ available: CGFloat) -> CGFloat {
        // Minimum 28pt, expand up to 44pt
        return min(max(available * 0.5, 28), 44)
    }
}

/// Settings button on the right of the top bar.
struct TopBarSettingsButton: View {
    var body: some View {
        Button {
            WindowsManager.shared.showSettings()
        } label: {
            Image(systemName: "gearshape.fill")
        }
        .buttonStyle(NookIconButtonStyle(size: 22))
        .help(String(localized: "Settings"))
    }
}
