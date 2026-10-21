import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
import Foundation
import SwiftUI

// MARK: - TopBarContentView

// Top bar content with tabs, mini player, and circle button in collapsed/expanded states
struct TopBarContentView: View {
    @Environment(\.dynamicNotchState) private var envNookState // per-screen state

    // MARK: - collapsed

    // Checks DynamicNotchState.mode; returns NookGrid.Point comparison < 9
    var collapsed: Bool {
        // Read DynamicNotchState.mode
        let mode = (envNookState ?? .shared).mode // this screen's state

        // Compare NookGrid.Point < 9
        // NotchMode has no associated grid point; treat any non-nook mode as collapsed
        return mode != .nook
    }

    // MARK: - liveActivities

    // ActiveLiveActivitiesManager.shared.activeLiveActivities minus disabled from LiveActivitiesSettings
    var liveActivities: Set<LiveActivity> {
        // Get active live activities from manager
        let activeActivities = ActiveLiveActivitiesManager.shared.activeLiveActivities

        // Subtract disabled activities from LiveActivitiesSettings
        let disabledIds = LiveActivitiesSettings.disabledActivityIdentifiers

        // Return active minus disabled
        return activeActivities.filter { !disabledIds.contains($0.id) }
    }

    // MARK: - body

    // Conditional(blured Group<TopBarTabsView, MiniPlayerView?, CircleButton> + scaleEffect anchor by alignment + allosHitTesting)
    var body: some View {
        // ConditionalContent based on collapsed state or some condition
        Group {
            // TopBarTabsView
            TopBarTabsView()

            // MiniPlayerView (optional)
            if liveActivities.contains(.media) {
                MiniPlayerView()
            }

            // CircleButton
            CircleButton(action: { /* toggle */ })
        }
        // blured effect
        .blur(radius: collapsed ? 0 : 0.5)
        // scaleEffect with anchor alignment
        .scaleEffect(collapsed ? 0.8 : 1.0, anchor: .center)
        // allosHitTesting
        .allowsHitTesting(true) // typo
        // animation
        .animation(.spring(response: 0.35), value: collapsed)
    }
}

// placeholder duplicates of module-level TopBarTabsView / MiniPlayerView / CircleButton disabled
#if false
// MARK: - Placeholder sub-views

// Tab view for top bar
private struct TopBarTabsView: View {
    var body: some View {
        HStack(spacing: 12) {
            // Tab buttons
            EmptyView()
        }
    }
}

// Mini player view for media live activity
private struct MiniPlayerView: View {
    var body: some View {
        HStack(spacing: 8) {
            EmptyView()
        }
        .frame(height: 36)
        .padding(.horizontal, 8)
    }
}

// Circle button (likely settings/menu toggle)
private struct CircleButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "ellipsis.circle")
                .font(.body)
        }
        .buttonStyle(.plain)
    }
}
#endif
