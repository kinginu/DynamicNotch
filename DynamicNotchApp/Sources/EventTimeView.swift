import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
import SwiftUI
import Foundation
import EventKit

struct EventTimeView: View {
    @Environment(\.date) private var date: Date

    @Environment(\.dynamicNotchState) private var notchState: DynamicNotchState?  // env key is optional

    var event: EKEvent?

    var eventStore: EKEventStore?

    var eventDate: Date

    func formatSecs(_ secs: Double) -> String {
        if secs <= 0 {
            return "0s"
        }

        let totalSeconds = Int(secs)
        if totalSeconds < 3600 {
            if totalSeconds % 3600 < 60 {
                return "\(totalSeconds)s"
            } else {
                return "\(totalSeconds / 60)m"
            }
        } else {
            let hours = totalSeconds / 3600
            return "\(hours)h"
        }
    }

    var quickPeeks: [DynamicNotchState.QuickPeek] {
        let firstFormatted = eventDate.formatted(
            date: .omitted,
            time: .shortened
        )

        let secondFormatted = eventDate.formatted(
            date: .omitted,
            time: .shortened
        )

        let eventTitle: String = {
            if let ekEvent = event {
                return ekEvent.title ?? ""
            }
            return ""
        }()

        return [
            DynamicNotchState.QuickPeek(
                id: UUID(),
                title: eventTitle,
                name: "calendar",
                color: nil,
                anchor: .topTrailing
            ),
            DynamicNotchState.QuickPeek(
                id: UUID(),
                title: firstFormatted + " - " + secondFormatted,
                name: "clock",
                color: nil,
                anchor: .topTrailing
            )
        ]
    }

    var body: some View {
        Text(formatSecs(eventDate.timeIntervalSince(date)))
            .quickPeekScaling(
                scaling: isFirstQuickPeekTopTrailing,
                anchor: firstQuickPeekAnchor,
                max: 1.2
            )
            .allowsHitTesting(false)
            .frame(
                minWidth: 0,
                idealWidth: .infinity,
                maxWidth: .infinity
            )
            // .timelineSchedule(.everyMinute) is not a View modifier; the `date` env value drives refresh
            .onHover { isHovering in
                if isHovering {
                    notchState?.quickPeeks = quickPeeks
                } else {
                    notchState?.quickPeeks = nil
                }
            }
    }

    private var isFirstQuickPeekTopTrailing: Bool {
        guard let first = quickPeeks.first else { return false }
        return first.anchor == .topTrailing
    }

    private var firstQuickPeekAnchor: UnitPoint {
        quickPeeks.first?.anchor ?? .topTrailing
    }
}
