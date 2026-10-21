import SwiftUI

/// Geometry of the closed-notch live activity row.
enum ClosedNotchActivityLayout {
    /// Extra width on each side of the hardware notch for the current live activity (0: nothing
    /// shown, the notch stays notch-sized). NotchView widens the closed footprint by twice this.
    @MainActor static func sideWidth(notchSize: CGSize) -> CGFloat {
        let center = LiveActivityCenter.shared
        return width(for: center.currentActivity, notchHeight: notchSize.height)
            + (center.timerIsMinimal ? TimerInsets.minimalExtraWidth : 0)
            + CaptureClosedNotchIndicator.extraSideWidth(activity: center.currentActivity, notchHeight: notchSize.height)
            + DownloadsClosedNotchIndicator.extraSideWidth(activity: center.currentActivity, notchHeight: notchSize.height) // F8: Downloads widget
    }

    /// Side width of `activity` (`LiveActivityDescriptor.sideWidth`); both sides are equally wide
    /// so the camera housing stays centred.
    @MainActor static func width(for activity: LiveActivity?, notchHeight: CGFloat) -> CGFloat {
        activity?.descriptor.sideWidth(notchHeight: notchHeight) ?? 0
    }

    /// Inset of the content from the footprint's outer (rounded) edge.
    static let outerInset: CGFloat = 10
}

/// The closed notch's top row: the current activity's two sides around the camera housing (the
/// centre `notchSize.width` stays empty), sized (notch width + 2 × side width) × notch height.
struct ClosedNotchActivitiesView: View {
    let notchSize: CGSize

    private var center: LiveActivityCenter { .shared }

    var body: some View {
        let activity = center.currentActivity
        let side = ClosedNotchActivityLayout.width(for: activity, notchHeight: notchSize.height)
        ZStack {
            if let activity, side > 0 {
                HStack(spacing: 0) {
                    LiveActivityView(side: .leading)
                        .padding(.leading, ClosedNotchActivityLayout.outerInset)
                        .padding(.trailing, 4)
                        .frame(width: side, height: notchSize.height, alignment: .leading)
                    Color.clear
                        .frame(width: notchSize.width, height: notchSize.height)
                        .allowsHitTesting(false)
                    LiveActivityView(side: .trailing)
                        .padding(.trailing, ClosedNotchActivityLayout.outerInset)
                        .padding(.leading, 4)
                        .frame(width: side, height: notchSize.height, alignment: .trailing)
                    // Dynamic Island "minimal": the timer's ring beside another activity
                    if center.timerIsMinimal {
                        TimerMinimalView(store: .shared)
                            .padding(.trailing, ClosedNotchActivityLayout.outerInset - 4)
                            .frame(width: TimerInsets.minimalExtraWidth, height: notchSize.height, alignment: .trailing)
                    }
                }
                .padding(.leading, center.timerIsMinimal ? TimerInsets.minimalExtraWidth : 0)
                .padding(.vertical, 4)
                .frame(height: notchSize.height)
                .environment(\.liveActivity, activity)
                .environment(\.powerMonitor, center.power)
                .id(activity)
                .transition(.scaleAndBlur)
            }
            if activity == nil { CaptureClosedNotchIndicator(notchSize: notchSize) } // Capture widget: recording
            if activity == nil { DownloadsClosedNotchIndicator(notchSize: notchSize) } // F8: Downloads widget progress
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.smooth(duration: 0.35), value: activity)
        // Display only — except while a timer alert rings: its "Stop" capsule is a button (hover
        // does not open the notch then, NotchViewModel.hoverOpenSuppressed); the rest of the row
        // opts out of hit testing again so clicks there still open the notch.
        .allowsHitTesting(activity == .timerExpired && !NookTimersStore.shared.alertingIDs.isEmpty)
    }
}
