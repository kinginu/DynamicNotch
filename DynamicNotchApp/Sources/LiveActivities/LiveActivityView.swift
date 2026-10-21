import SwiftUI

/// One side (left or right of the camera housing) of the closed-notch live activity.
/// `ClosedNotchActivitiesView` injects `\.liveActivity` and `\.powerMonitor` and sizes each side.
struct LiveActivityView: View {
    enum ActivitySide: Equatable, Hashable {
        case leading
        case trailing
    }

    @Environment(\.liveActivity) private var activity: LiveActivity?
    @Environment(\.powerMonitor) private var power: PowerMonitor?

    var side: ActivitySide = .leading

    private var center: LiveActivityCenter { .shared }

    var body: some View {
        ZStack {
            if let activity {
                content(for: activity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: side == .leading ? .leading : .trailing)
        .transition(.scaleAndBlur)
    }

    @ViewBuilder
    private func content(for activity: LiveActivity) -> some View {
        switch (activity, side) {
        case (.media, .leading):
            MiniAlbumCoverView()
        case (.media, .trailing):
            AudioAnimationView()

        case (.battery, _):
            BatteryLiveActivityView(side: side, power: power)

        case (.calendar, _):
            CalendarLiveActivityView(side: side, event: center.upcomingEvent)

        case (.timerExpired, _):
            TimerLiveActivityView(side: side, store: .shared, fallbackLabel: center.expiredTimerLabel)

        case (.pomodoro, _):
            PomodoroLiveActivityView(side: side, store: .shared)

        case (.tray, .leading):
            Image(systemName: "tray.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.nonShockingWhite)
        case (.tray, .trailing):
            TrayFilesCountView()

        case (.keepAwake, _):
            KeepAwakeLiveActivityView(side: side)

        #if canImport(FanControlKit) // fan-control-integration.md (f)
        case (.fanAlert, .leading):
            FanControlAlertView(part: .leading)
        case (.fanAlert, .trailing):
            FanControlAlertView(part: .trailing)
        #endif

        case (.hud, _): HUDLiveActivityView(side: side) // F5: icon | level bar

        case (.nextUp, _):
            NextUpLiveActivityView(side: side)

        // bluetooth / volume / update: the activity's symbol on the leading side only
        case (_, .leading):
            LiveActivityIconView(activity: activity)
        default:
            EmptyView()
        }
    }
}
