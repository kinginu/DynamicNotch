import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

// Metrics of the timer's closed-notch live activity (Dynamic Island compact / minimal / alert
//   sizes), used by ClosedNotchActivityLayout (LiveActivities/ClosedNotchActivitiesView.swift) and LiveActivityView.
struct TimerInsets {
    /// iOS timer tint (the Clock app's orange).
    static let tint = Color.orange

    /// Side width of the compact presentation (ring | remaining time). Wide enough for "H:MM:SS".
    static func compactSideWidth(notchHeight: CGFloat, showsHours: Bool) -> CGFloat {
        let h = max(notchHeight, 24)
        return max(h + 8, showsHours ? 76 : 62)
    }

    /// Side width of the ended-timer alert (bell + label | Stop).
    static let alertSideWidth: CGFloat = 104

    /// Diameter of the minimal ring shown beside another activity.
    static let minimalDiameter: CGFloat = 16
    /// Extra width added on each side of the notch for the minimal ring.
    static let minimalExtraWidth: CGFloat = minimalDiameter + 8

    /// Ring line width in the closed notch.
    static let closedRingLineWidth: CGFloat = 2.5
}
